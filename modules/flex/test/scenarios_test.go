package test

import (
	"context"
	"fmt"
	"testing"

	"github.com/runs-on/terraform-aws-runs-on/modules/flex/test/internal/validationimage"
)

func TestScenarioMatrix(t *testing.T) {
	testCases := []struct {
		name              string
		validationEnv     string
		skipInShort       bool
		configure         func(*ScenarioConfig)
		successMessages   []string
		validationProfile BaselineValidationOptions
	}{
		{
			name:          "basic",
			validationEnv: validationimage.ScenarioBasic,
			configure:     func(*ScenarioConfig) {},
			successMessages: []string{
				"Basic scenario deployment successful!",
			},
			validationProfile: BaselineValidationOptions{
				Functional: true,
			},
		},
		{
			name:          "private",
			validationEnv: validationimage.ScenarioPrivate,
			skipInShort:   true,
			configure: func(cfg *ScenarioConfig) {
				cfg.EnableNAT = true
				cfg.PrivateMode = "true"
			},
			successMessages: []string{
				"Private networking deployment successful!",
			},
			validationProfile: BaselineValidationOptions{
				Functional: true,
			},
		},
		{
			name:          "full",
			validationEnv: validationimage.ScenarioFull,
			skipInShort:   true,
			configure: func(cfg *ScenarioConfig) {
				cfg.EnableNAT = true
				cfg.EnableEFS = true
				cfg.EnableECR = true
			},
			successMessages: []string{
				"Full-featured deployment successful!",
			},
			validationProfile: BaselineValidationOptions{
				Functional: true,
			},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			if tc.skipInShort && testing.Short() {
				t.Skip("Skipping expensive scenario in short mode")
			}

			requireValidationEnv(t, tc.validationEnv, validationimage.EnvModeDirect)

			cfg := DefaultScenarioConfig()
			tc.configure(&cfg)

			result := deployScenario(t, cfg)
			clients := NewAWSClients(context.Background())

			runBaselineValidationProfile(t, clients, result, tc.validationProfile)

			for _, message := range tc.successMessages {
				fmt.Printf("\n%s\n", message)
			}
			fmt.Printf("   Stack: %s\n", result.StackName())
			fmt.Printf("   Ingress: %s\n", result.IngressURL())
			if result.Config.PrivateMode != "" && result.Config.PrivateMode != "false" {
				fmt.Printf("   Private Mode: %s\n", result.Config.PrivateMode)
			}
			if result.Config.EnableEFS {
				fmt.Printf("   EFS: %s\n", result.EFSFileSystemID())
			}
			if result.Config.EnableECR {
				fmt.Printf("   ECR: %s\n", result.ECRURL())
			}
		})
	}
}
