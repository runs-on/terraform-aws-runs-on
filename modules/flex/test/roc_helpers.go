package test

import (
	"archive/zip"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/google/go-github/v84/github"
	"github.com/stretchr/testify/require"
)

type doctorArchiveCheck struct {
	Name   string `json:"name"`
	Status string `json:"status"`
}

type doctorArchiveResult struct {
	Checks []doctorArchiveCheck `json:"checks"`
}

func repoRootForTests(t *testing.T) string {
	t.Helper()

	wd, err := os.Getwd()
	require.NoError(t, err, "Failed to resolve terraform test working directory")

	repoRoot := filepath.Clean(filepath.Join(wd, "../../../.."))
	_, err = os.Stat(filepath.Join(repoRoot, "cli", "main.go"))
	require.NoError(t, err, "Failed to find monorepo root from %s", wd)
	return repoRoot
}

func buildRocBinary(t *testing.T) string {
	t.Helper()

	repoRoot := repoRootForTests(t)
	outputPath := filepath.Join(t.TempDir(), "roc")

	cmd := exec.Command("mise", "exec", "--", "go", "build", "-o", outputPath, ".")
	cmd.Dir = filepath.Join(repoRoot, "cli")
	cmd.Env = os.Environ()

	output, err := cmd.CombinedOutput()
	require.NoErrorf(t, err, "Failed to build roc from local source:\n%s", string(output))
	return outputPath
}

func workflowJobsForRun(t *testing.T, client *github.Client, repo string, runID int64) []*github.WorkflowJob {
	t.Helper()

	owner, repoName, err := parseRepo(repo)
	require.NoError(t, err, "Invalid repo format")

	jobs, _, err := client.Actions.ListWorkflowJobs(context.Background(), owner, repoName, runID, &github.ListWorkflowJobsOptions{
		Filter: "all",
	})
	require.NoError(t, err, "Failed to list workflow jobs for run %d", runID)
	require.NotEmpty(t, jobs.Jobs, "Expected workflow jobs for run %d", runID)
	return jobs.Jobs
}

func selectRunsOnWorkflowJob(t *testing.T, client *github.Client, repo string, runID int64) *github.WorkflowJob {
	t.Helper()

	for _, job := range workflowJobsForRun(t, client, repo, runID) {
		if strings.TrimSpace(job.GetRunnerName()) == "" {
			continue
		}
		if job.GetStatus() != "completed" && job.GetStatus() != "in_progress" {
			continue
		}
		return job
	}

	require.FailNowf(t, "No RunsOn workflow job found", "Expected at least one workflow job for run %d with a runner name", runID)
	return nil
}

func sinceArgFromStart(startTime time.Time) string {
	seconds := max(int(time.Since(startTime).Seconds())+120, 120)
	return fmt.Sprintf("%ds", seconds)
}

func runROCCommand(t *testing.T, rocPath, stackName string, timeout time.Duration, args ...string) (string, error) {
	t.Helper()

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	allArgs := append([]string{"--stack", stackName}, args...)
	cmd := exec.CommandContext(ctx, rocPath, allArgs...)
	cmd.Dir = t.TempDir()
	cmd.Env = os.Environ()

	output, err := cmd.CombinedOutput()
	if ctx.Err() != nil {
		return string(output), fmt.Errorf("roc %s: %w", strings.Join(args, " "), ctx.Err())
	}
	return string(output), err
}

func waitForROCCheck(t *testing.T, timeout, interval time.Duration, run func() (string, error), validate func(string) error) string {
	t.Helper()

	deadline := time.Now().Add(timeout)
	var lastOutput string
	var lastErr error
	var lastValidateErr error

	for {
		output, err := run()
		lastOutput = output
		lastErr = err
		lastValidateErr = nil
		if err == nil {
			if validateErr := validate(output); validateErr == nil {
				return output
			} else {
				lastValidateErr = validateErr
			}
		}

		if time.Now().After(deadline) {
			if lastErr != nil {
				require.FailNowf(t, "roc command never succeeded", "last error: %v\noutput:\n%s", lastErr, lastOutput)
			}
			require.FailNowf(t, "roc output never matched expected shape", "last validation error: %v\noutput:\n%s", lastValidateErr, lastOutput)
		}
		time.Sleep(interval)
	}
}

func extractDoctorArchivePath(output string) string {
	matches := regexp.MustCompile(`(?m)^Full results exported to: (.+)$`).FindStringSubmatch(output)
	if len(matches) != 2 {
		return ""
	}
	return strings.TrimSpace(matches[1])
}

func readDoctorArchive(t *testing.T, archivePath string) (doctorArchiveResult, map[string]string) {
	t.Helper()

	reader, err := zip.OpenReader(archivePath)
	require.NoError(t, err, "Failed to open doctor archive %s", archivePath)
	defer reader.Close()

	files := make(map[string]string, len(reader.File))
	var result doctorArchiveResult

	for _, file := range reader.File {
		rc, err := file.Open()
		require.NoError(t, err, "Failed to open archive file %s", file.Name)
		content, err := io.ReadAll(rc)
		rc.Close()
		require.NoError(t, err, "Failed to read archive file %s", file.Name)

		files[file.Name] = string(content)
		if file.Name == "checks.json" {
			err = json.Unmarshal(content, &result)
			require.NoError(t, err, "Failed to parse checks.json")
		}
	}

	return result, files
}
