package validationimage

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
)

const (
	ScenarioBasic       = "basic"
	ScenarioPrivate     = "private"
	ScenarioFull        = "full"
	ScenarioIntegration = "integration"
)

type EnvMode string

const (
	EnvModeDirect      EnvMode = "direct"
	EnvModeWithCIImage EnvMode = "with-ci-image"
)

type TagContext struct {
	Version   string
	Scenario  string
	GitSHA    string
	IsCI      bool
	PRNumber  string
	LocalUser string
	Timestamp int64
}

var invalidTagPart = regexp.MustCompile(`[^a-z0-9]+`)

func BuildTag(ctx TagContext) (string, error) {
	version := strings.TrimSpace(ctx.Version)
	if version == "" {
		return "", fmt.Errorf("version is required")
	}

	scenario, err := NormalizeScenario(ctx.Scenario)
	if err != nil {
		return "", err
	}

	sha := shortSHA(ctx.GitSHA)
	if sha == "" {
		return "", fmt.Errorf("git sha is required")
	}

	if ctx.IsCI {
		if pr := sanitizeTagPart(ctx.PRNumber); pr != "" {
			return fmt.Sprintf("%s-terraform-%s-pr-%s-%s", version, scenario, pr, sha), nil
		}
		return fmt.Sprintf("%s-terraform-%s-main-%s", version, scenario, sha), nil
	}

	user := sanitizeTagPart(ctx.LocalUser)
	if user == "" {
		return "", fmt.Errorf("local user is required")
	}
	if ctx.Timestamp <= 0 {
		return "", fmt.Errorf("timestamp is required for local validation tags")
	}

	return fmt.Sprintf("%s-terraform-%s-local-%s-%s-%d", version, scenario, user, sha, ctx.Timestamp), nil
}

func NormalizeScenario(scenario string) (string, error) {
	switch strings.TrimSpace(scenario) {
	case ScenarioBasic, ScenarioPrivate, ScenarioFull, ScenarioIntegration:
		return scenario, nil
	default:
		return "", fmt.Errorf("unsupported validation scenario %q", scenario)
	}
}

func RequiredEnvVars(scenario string, mode EnvMode) ([]string, error) {
	scenario, err := NormalizeScenario(scenario)
	if err != nil {
		return nil, err
	}

	required := []string{"RUNS_ON_LICENSE_KEY"}
	if mode == EnvModeDirect {
		required = append(required, "RUNS_ON_APP_IMAGE", "RUNS_ON_APP_TAG")
	}

	if scenario == ScenarioIntegration {
		required = append(required,
			"RUNS_ON_TEST_REPO",
			"RUNS_ON_TEST_WORKFLOW",
			"GITHUB_APP_ID",
			"GITHUB_APP_PRIVATE_KEY",
			"GITHUB_APP_WEBHOOK_SECRET",
			"GITHUB_APP_CLIENT_ID",
			"GITHUB_APP_CLIENT_SECRET",
		)
	}

	return required, nil
}

func MissingEnvVars(required []string, lookup func(string) string) []string {
	missing := make([]string, 0, len(required))
	for _, name := range required {
		if strings.TrimSpace(lookup(name)) == "" {
			missing = append(missing, name)
		}
	}
	sort.Strings(missing)
	return missing
}

func sanitizeTagPart(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	value = invalidTagPart.ReplaceAllString(value, "-")
	value = strings.Trim(value, "-")
	return value
}

func shortSHA(sha string) string {
	sha = strings.TrimSpace(sha)
	if len(sha) > 12 {
		return sha[:12]
	}
	return sha
}
