package main

import (
	"errors"
	"reflect"
	"testing"
)

func TestBuildContainerArtifactsRunsScriptFromRepoRoot(t *testing.T) {
	t.Parallel()

	var gotRepoRoot string
	var gotEnv []string
	var gotName string
	var gotArgs []string

	err := buildContainerArtifacts("/repo", func(repoRoot string, env []string, name string, args ...string) error {
		gotRepoRoot = repoRoot
		gotEnv = env
		gotName = name
		gotArgs = append([]string(nil), args...)
		return nil
	})
	if err != nil {
		t.Fatalf("buildContainerArtifacts returned error: %v", err)
	}

	if gotRepoRoot != "/repo" {
		t.Fatalf("repoRoot = %q, want %q", gotRepoRoot, "/repo")
	}
	if gotEnv != nil {
		t.Fatalf("env = %#v, want nil", gotEnv)
	}
	if gotName != "bash" {
		t.Fatalf("name = %q, want %q", gotName, "bash")
	}
	if want := []string{"./scripts/build-container-artifacts.sh"}; !reflect.DeepEqual(gotArgs, want) {
		t.Fatalf("args = %#v, want %#v", gotArgs, want)
	}
}

func TestBuildContainerArtifactsWrapsRunnerError(t *testing.T) {
	t.Parallel()

	sentinel := errors.New("boom")
	err := buildContainerArtifacts("/repo", func(repoRoot string, env []string, name string, args ...string) error {
		return sentinel
	})
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	if !errors.Is(err, sentinel) {
		t.Fatalf("expected wrapped error %v, got %v", sentinel, err)
	}
}
