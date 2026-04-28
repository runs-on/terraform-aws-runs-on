package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/runs-on/terraform-aws-runs-on/flex/test/internal/validationimage"
)

type buildResult struct {
	ImageRef string `json:"image_ref"`
	ImageTag string `json:"image_tag"`
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	repoRoot, err := findRepoRoot()
	if err != nil {
		return err
	}

	flags := flag.NewFlagSet("with-ci-image", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	scenario := flags.String("scenario", "", "Validation scenario (basic, private, full, integration)")
	if err := flags.Parse(os.Args[1:]); err != nil {
		return err
	}
	if strings.TrimSpace(*scenario) == "" {
		return fmt.Errorf("--scenario is required")
	}

	command := flags.Args()
	if len(command) == 0 {
		return fmt.Errorf("command to execute is required")
	}
	if command[0] == "--" {
		command = command[1:]
	}
	if len(command) == 0 {
		return fmt.Errorf("command to execute is required")
	}

	requiredEnv, err := validationimage.RequiredEnvVars(*scenario, validationimage.EnvModeWithCIImage)
	if err != nil {
		return err
	}
	missingEnv := validationimage.MissingEnvVars(requiredEnv, os.Getenv)
	if len(missingEnv) > 0 {
		return fmt.Errorf("missing required env vars for %s validation: %s", *scenario, strings.Join(missingEnv, ", "))
	}

	version, err := readVersion(filepath.Join(repoRoot, "VERSION"))
	if err != nil {
		return err
	}
	tag, err := validationimage.BuildTag(validationimage.TagContext{
		Version:   version,
		Scenario:  *scenario,
		GitSHA:    gitSHA(repoRoot),
		IsCI:      os.Getenv("GITHUB_ACTIONS") == "true",
		PRNumber:  githubPRNumber(),
		LocalUser: localUser(),
		Timestamp: time.Now().Unix(),
	})
	if err != nil {
		return err
	}

	fmt.Fprintf(os.Stderr, "Building release artifacts for Terraform %s validation image...\n", *scenario)
	fmt.Fprintf(os.Stderr, "Logging into ECR Public for Terraform %s validation...\n", *scenario)
	if err := runStreaming(repoRoot, nil, "make", "ecr-public-login"); err != nil {
		return fmt.Errorf("log in to ECR Public: %w", err)
	}

	fmt.Fprintf(os.Stderr, "Building and pushing Terraform validation image %s...\n", tag)
	build, err := buildCIImage(repoRoot, tag)
	if err != nil {
		return err
	}

	fmt.Fprintf(os.Stderr, "Using RUNS_ON_APP_IMAGE=%s\n", build.ImageRef)
	fmt.Fprintf(os.Stderr, "Using RUNS_ON_APP_TAG=%s\n", build.ImageTag)

	childEnv := append(os.Environ(),
		"RUNS_ON_APP_IMAGE="+build.ImageRef,
		"RUNS_ON_APP_TAG="+build.ImageTag,
	)

	if err := runStreaming(repoRoot, childEnv, command[0], command[1:]...); err != nil {
		return err
	}

	return nil
}

func findRepoRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("get current working directory: %w", err)
	}

	for {
		if _, err := os.Stat(filepath.Join(dir, "release", "config.yaml")); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("could not find repo root from %s", dir)
		}
		dir = parent
	}
}

func readVersion(path string) (string, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("read version file: %w", err)
	}
	version := strings.TrimSpace(string(content))
	if version == "" {
		return "", fmt.Errorf("version file %s is empty", path)
	}
	return version, nil
}

func gitSHA(repoRoot string) string {
	if sha := strings.TrimSpace(os.Getenv("GITHUB_SHA")); sha != "" {
		return sha
	}

	output, err := exec.Command("git", "-C", repoRoot, "rev-parse", "HEAD").Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(output))
}

func localUser() string {
	if user := strings.TrimSpace(os.Getenv("USER")); user != "" {
		return user
	}
	output, err := exec.Command("whoami").Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(output))
}

var pullRefPattern = regexp.MustCompile(`^refs/pull/([0-9]+)/`)

func githubPRNumber() string {
	match := pullRefPattern.FindStringSubmatch(strings.TrimSpace(os.Getenv("GITHUB_REF")))
	if len(match) == 2 {
		return match[1]
	}
	return ""
}

func buildCIImage(repoRoot, tag string) (buildResult, error) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd := exec.Command("go", "run", "./cmd/releasectl", "build", "image", "--registry-alias", "ci", "--tag", tag, "--push", "--compression", "fast")
	cmd.Dir = repoRoot
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		if stderr.Len() > 0 {
			fmt.Fprint(os.Stderr, stderr.String())
		}
		return buildResult{}, fmt.Errorf("build validation image: %w", err)
	}

	if stderr.Len() > 0 {
		fmt.Fprint(os.Stderr, stderr.String())
	}

	var result buildResult
	if err := json.Unmarshal(stdout.Bytes(), &result); err != nil {
		return buildResult{}, fmt.Errorf("parse build output: %w", err)
	}
	if strings.TrimSpace(result.ImageRef) == "" || strings.TrimSpace(result.ImageTag) == "" {
		return buildResult{}, fmt.Errorf("build output did not include image_ref and image_tag")
	}

	return result, nil
}

type streamRunner func(repoRoot string, env []string, name string, args ...string) error

func runStreaming(repoRoot string, env []string, name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Dir = repoRoot
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if env != nil {
		cmd.Env = env
	}

	if err := cmd.Run(); err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			os.Exit(exitErr.ExitCode())
		}
		return err
	}

	return nil
}
