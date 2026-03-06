package test

import (
	"context"
	"fmt"
	"testing"
)

// TestScenarioBasic tests the basic deployment scenario with all validations.
func TestScenarioBasic(t *testing.T) {
	cfg := DefaultScenarioConfig()

	runScenario(t, cfg, func(t *testing.T, r ScenarioResult) {
		clients := NewAWSClients(context.Background())

		runOutputValidations(t, r)
		runSecurityValidations(t, clients, r)
		runComplianceValidations(t, clients, r)
		runWiringValidations(t, clients, r)
		runTaggingValidations(t, clients, r)
		runAdvancedValidations(t, r)

		t.Run("Functional", func(t *testing.T) {
			runFunctionalValidations(t, clients, r)
		})

		fmt.Printf("\nBasic scenario deployment successful!\n")
		fmt.Printf("   Stack: %s\n", r.StackName())
		fmt.Printf("   App Runner: %s\n", r.AppRunnerURL())
	})
}

// TestScenarioFullFeatured tests full-featured scenario with all options (NAT + EFS + ECR).
func TestScenarioFullFeatured(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping expensive full-featured test (requires NAT + EFS + ECR)")
	}

	cfg := DefaultScenarioConfig()
	cfg.EnableNAT = true
	cfg.EnableEFS = true
	cfg.EnableECR = true

	runScenario(t, cfg, func(t *testing.T, r ScenarioResult) {
		clients := NewAWSClients(context.Background())

		runOutputValidations(t, r)
		runSecurityValidations(t, clients, r)
		runComplianceValidations(t, clients, r)
		runWiringValidations(t, clients, r)
		runTaggingValidations(t, clients, r)
		runAdvancedValidations(t, r)

		t.Run("Functional", func(t *testing.T) {
			runFunctionalValidations(t, clients, r)
		})

		fmt.Printf("\nFull-featured deployment successful!\n")
		fmt.Printf("   Stack: %s\n", r.StackName())
		fmt.Printf("   App Runner: %s\n", r.AppRunnerURL())
		fmt.Printf("   EFS: %s\n", r.EFSFileSystemID())
		fmt.Printf("   ECR: %s\n", r.ECRURL())
	})
}

// TestScenarioPrivateNetworking tests deployment with private networking enabled.
func TestScenarioPrivateNetworking(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping expensive private networking test")
	}

	cfg := DefaultScenarioConfig()
	cfg.EnableNAT = true
	cfg.PrivateMode = "true"

	runScenario(t, cfg, func(t *testing.T, r ScenarioResult) {
		clients := NewAWSClients(context.Background())

		runOutputValidations(t, r)
		runSecurityValidations(t, clients, r)
		runComplianceValidations(t, clients, r)
		runWiringValidations(t, clients, r)
		runTaggingValidations(t, clients, r)
		runAdvancedValidations(t, r)

		t.Run("Functional", func(t *testing.T) {
			runFunctionalValidations(t, clients, r)
		})

		fmt.Printf("\nPrivate networking deployment successful!\n")
		fmt.Printf("   Stack: %s\n", r.StackName())
		fmt.Printf("   App Runner: %s\n", r.AppRunnerURL())
		fmt.Printf("   Private Mode: %s\n", cfg.PrivateMode)
	})
}
