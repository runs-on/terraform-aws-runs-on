package validationimage

import (
	"os"
	"testing"
)

func TestBuildTagLocal(t *testing.T) {
	tag, err := BuildTag(TagContext{
		Version:   "v2.12.1",
		Scenario:  ScenarioBasic,
		GitSHA:    "1234567890abcdef",
		LocalUser: "Jane Doe",
		Timestamp: 1700000000,
	})
	if err != nil {
		t.Fatalf("BuildTag returned error: %v", err)
	}

	want := "v2.12.1-terraform-basic-local-jane-doe-1234567890ab-1700000000"
	if tag != want {
		t.Fatalf("BuildTag() = %q, want %q", tag, want)
	}
}

func TestBuildTagCIPR(t *testing.T) {
	tag, err := BuildTag(TagContext{
		Version:  "v2.12.1",
		Scenario: ScenarioPrivate,
		GitSHA:   "abcdef1234567890",
		IsCI:     true,
		PRNumber: "42",
	})
	if err != nil {
		t.Fatalf("BuildTag returned error: %v", err)
	}

	want := "v2.12.1-terraform-private-pr-42-abcdef123456"
	if tag != want {
		t.Fatalf("BuildTag() = %q, want %q", tag, want)
	}
}

func TestBuildTagCIMain(t *testing.T) {
	tag, err := BuildTag(TagContext{
		Version:  "v2.12.1",
		Scenario: ScenarioFull,
		GitSHA:   "fedcba6543210000",
		IsCI:     true,
	})
	if err != nil {
		t.Fatalf("BuildTag returned error: %v", err)
	}

	want := "v2.12.1-terraform-full-main-fedcba654321"
	if tag != want {
		t.Fatalf("BuildTag() = %q, want %q", tag, want)
	}
}

func TestRequiredEnvVarsDirect(t *testing.T) {
	required, err := RequiredEnvVars(ScenarioIntegration, EnvModeDirect)
	if err != nil {
		t.Fatalf("RequiredEnvVars returned error: %v", err)
	}

	found := map[string]bool{}
	for _, name := range required {
		found[name] = true
	}

	for _, want := range []string{
		"RUNS_ON_LICENSE_KEY",
		"RUNS_ON_APP_IMAGE",
		"RUNS_ON_APP_TAG",
		"RUNS_ON_TEST_REPO",
		"RUNS_ON_TEST_WORKFLOW",
		"GITHUB_APP_ID",
		"GITHUB_APP_PRIVATE_KEY",
		"GITHUB_APP_WEBHOOK_SECRET",
		"GITHUB_APP_CLIENT_ID",
		"GITHUB_APP_CLIENT_SECRET",
	} {
		if !found[want] {
			t.Fatalf("required env vars missing %q from %#v", want, required)
		}
	}
}

func TestRequiredEnvVarsWithCIImageOmitsImageVars(t *testing.T) {
	required, err := RequiredEnvVars(ScenarioBasic, EnvModeWithCIImage)
	if err != nil {
		t.Fatalf("RequiredEnvVars returned error: %v", err)
	}

	for _, unexpected := range []string{"RUNS_ON_APP_IMAGE", "RUNS_ON_APP_TAG"} {
		for _, name := range required {
			if name == unexpected {
				t.Fatalf("required env vars unexpectedly included %q", unexpected)
			}
		}
	}
}

func TestMissingEnvVars(t *testing.T) {
	t.Setenv("RUNS_ON_LICENSE_KEY", "set")

	missing := MissingEnvVars([]string{"RUNS_ON_LICENSE_KEY", "RUNS_ON_APP_IMAGE", "RUNS_ON_APP_TAG"}, os.Getenv)
	if len(missing) != 2 {
		t.Fatalf("MissingEnvVars() len = %d, want 2 (%v)", len(missing), missing)
	}
	if missing[0] != "RUNS_ON_APP_IMAGE" || missing[1] != "RUNS_ON_APP_TAG" {
		t.Fatalf("MissingEnvVars() = %#v, want RUNS_ON_APP_IMAGE,RUNS_ON_APP_TAG", missing)
	}
}
