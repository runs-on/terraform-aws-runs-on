package test

import (
	"maps"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"
	tfjson "github.com/hashicorp/terraform-json"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// planVars returns the minimum required variables for `tofu plan` with dummy values.
// Overrides are applied on top of the base set.
func planVars(overrides map[string]any) map[string]any {
	vars := map[string]any{
		"github_organization":                "test-org",
		"license_key":                        "test-license-key",
		"vpc_id":                             "vpc-12345678",
		"public_subnet_ids":                  []string{"subnet-11111111"},
		"email":                              "test@example.com",
		"stack_name":                         "test-plan",
		"environment":                        "test",
		"enable_efs":                         false,
		"enable_ecr":                         false,
		"enable_waf":                         false,
		"enable_admin_routes":                true,
		"private_mode":                       "false",
		"security_group_ids":                 []string{},
		"app_image":                          "public.ecr.aws/c5h5o9k1/runs-on/runs-on:test",
		"app_tag":                            "test",
		"force_destroy_buckets":              true,
		"force_delete_ecr":                   true,
		"prevent_destroy_optional_resources": false,
	}
	maps.Copy(vars, overrides)
	return vars
}

func newPlanOptions(t *testing.T, overrides map[string]any) *terraform.Options {
	t.Helper()

	terraformRoot := copyTerraformRoot(t, t.Name())
	return &terraform.Options{
		TerraformDir:    terraformRoot,
		TerraformBinary: "tofu",
		Vars:            planVars(overrides),
		PlanFilePath:    filepath.Join(terraformRoot, "plan.out"),
		NoColor:         true,
	}
}

func loadPlan(t *testing.T, overrides map[string]any) *terraform.PlanStruct {
	t.Helper()

	options := newPlanOptions(t, overrides)
	mustRunTerraformCommandQuietly(t, options, "init")
	mustRunTerraformCommandQuietly(t, options, "plan", "-input=false", "-lock=false")
	showOut := mustRunTerraformCommandQuietly(t, options, "show", "-json")

	plan, err := terraform.ParsePlanJSON(showOut)
	require.NoError(t, err, "terraform show output should parse as a structured plan")
	return plan
}

func mustRunTerraformCommandQuietly(t *testing.T, options *terraform.Options, args ...string) string {
	t.Helper()

	out, err := runTerraformCommandQuietlyWithRetry(t, options, args...)
	require.NoErrorf(t, err, "terraform %s failed.\nCaptured output:\n%s", strings.Join(args, " "), out)
	return out
}

func runTerraformCommandQuietly(t *testing.T, options *terraform.Options, args ...string) (string, error) {
	t.Helper()

	commandArgs := terraform.FormatArgs(options, args...)
	cmd := shell.Command{
		Command:    options.TerraformBinary,
		Args:       commandArgs,
		WorkingDir: options.TerraformDir,
		Env:        options.EnvVars,
		Logger:     logger.Discard,
		Stdin:      options.Stdin,
	}

	return shell.RunCommandAndGetOutputE(t, cmd)
}

func runTerraformCommandQuietlyWithRetry(t *testing.T, options *terraform.Options, args ...string) (string, error) {
	t.Helper()

	out, err := runTerraformCommandQuietly(t, options, args...)
	if err == nil || !isRetryableTerraformCommandError(args, out) {
		return out, err
	}

	for attempt := 2; attempt <= 3; attempt++ {
		time.Sleep(time.Duration(attempt-1) * 2 * time.Second)

		out, err = runTerraformCommandQuietly(t, options, args...)
		if err == nil || !isRetryableTerraformCommandError(args, out) {
			return out, err
		}
	}

	return out, err
}

func isRetryableTerraformCommandError(args []string, out string) bool {
	if len(args) == 0 || args[0] != "init" {
		return false
	}

	return strings.Contains(out, "Failed to install provider") ||
		strings.Contains(out, "the request failed after") ||
		strings.Contains(out, "Client.Timeout exceeded")
}

func trimModulePath(address string) string {
	for strings.HasPrefix(address, "module.") {
		trimmed := strings.TrimPrefix(address, "module.")
		_, after, ok := strings.Cut(trimmed, ".")
		if !ok {
			return address
		}
		address = after
	}
	return address
}

func hasResourceChangePrefix(plan *terraform.PlanStruct, prefix string) bool {
	for address := range plan.ResourceChangesMap {
		if strings.HasPrefix(trimModulePath(address), prefix) {
			return true
		}
	}
	return false
}

func countResourceActions(plan *terraform.PlanStruct, matcher func(tfjson.Actions) bool) int {
	count := 0
	for _, change := range plan.ResourceChangesMap {
		if change == nil || change.Change == nil {
			continue
		}
		if matcher(change.Change.Actions) {
			count++
		}
	}
	return count
}

func TestTrimModulePath(t *testing.T) {
	t.Parallel()

	assert.Equal(t,
		"aws_lambda_function.github_waf_sync[0]",
		trimModulePath("module.control_plane.aws_lambda_function.github_waf_sync[0]"))
	assert.Equal(t,
		"aws_iam_role_policy_attachment.ec2_custom[0]",
		trimModulePath("module.compute.aws_iam_role_policy_attachment.ec2_custom[0]"))
	assert.Equal(t,
		"aws_efs_mount_target.az1[0]",
		trimModulePath("module.extras.aws_efs_mount_target.az1[0]"))
	assert.Equal(t,
		"aws_security_group.runners",
		trimModulePath("aws_security_group.runners"))
}

// TestPlanConditionalResources validates that feature flags control which resources are planned.
// These tests run `tofu plan` with dummy values and inspect the structured plan output.
func TestPlanConditionalResources(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name          string
		overrides     map[string]any
		expectPresent []string
		expectAbsent  []string
	}{
		{
			name: "WAFManagedGithubDotCom",
			overrides: map[string]any{
				"enable_waf": true,
			},
			expectPresent: []string{
				"aws_lambda_function.github_waf_sync",
				"aws_wafv2_web_acl.this",
				"aws_lambda_invocation.github_waf_sync_seed",
			},
		},
		{
			name: "WAFUserManagedOverride",
			overrides: map[string]any{
				"enable_waf":                 true,
				"public_ingress_web_acl_arn": "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/custom/abcd1234",
			},
			expectAbsent: []string{
				"aws_lambda_function.github_waf_sync",
			},
		},
		{
			name: "DisableAdminRoutes",
			overrides: map[string]any{
				"enable_admin_routes": false,
			},
			expectAbsent: []string{
				"aws_lambda_function.github_apps_setup",
				"aws_api_gateway_resource.setup",
				"aws_api_gateway_resource.readyz",
			},
		},
		{
			name:      "BaselineNoOptional",
			overrides: map[string]any{},
			expectPresent: []string{
				"aws_lambda_function.github_runner_cache_refresh",
				"aws_scheduler_schedule.github_runner_cache_refresh",
			},
			expectAbsent: []string{
				"aws_efs_file_system",
				"aws_ecr_repository",
			},
		},
		{
			name: "EFSOnly",
			overrides: map[string]any{
				"enable_efs": true,
			},
			expectPresent: []string{
				"aws_efs_file_system.this_",
				"aws_efs_mount_target.az",
				"aws_security_group.efs",
			},
			expectAbsent: []string{
				"aws_ecr_repository.ephemeral_",
			},
		},
		{
			name: "ECROnly",
			overrides: map[string]any{
				"enable_ecr": true,
			},
			expectPresent: []string{
				"aws_ecr_repository.ephemeral_",
				"aws_ecr_lifecycle_policy.ephemeral",
			},
			expectAbsent: []string{
				"aws_efs_file_system.this_",
			},
		},
		{
			name: "PrivateModeTrue",
			overrides: map[string]any{
				"private_mode":       "true",
				"private_subnet_ids": []string{"subnet-22222222"},
			},
		},
		{
			name: "PrivateModeWithDelay",
			overrides: map[string]any{
				"private_mode":       "true",
				"private_subnet_ids": []string{"subnet-22222222"},
				"private_mode_delay": "60s",
			},
			expectPresent: []string{
				"time_sleep",
			},
		},
		{
			name: "AllFeatures",
			overrides: map[string]any{
				"enable_efs":         true,
				"enable_ecr":         true,
				"private_mode":       "true",
				"private_subnet_ids": []string{"subnet-22222222"},
			},
			expectPresent: []string{
				"aws_efs_file_system.this_",
				"aws_ecr_repository.ephemeral_",
			},
		},
		{
			name: "SGCreatedWhenEmpty",
			overrides: map[string]any{
				"security_group_ids": []string{},
			},
			expectPresent: []string{
				"aws_security_group.runners",
			},
		},
		{
			name: "SGNotCreatedWhenProvided",
			overrides: map[string]any{
				"security_group_ids": []string{"sg-12345678"},
			},
			expectAbsent: []string{
				"aws_security_group.runners",
			},
		},
		{
			name: "AppCustomPolicy",
			overrides: map[string]any{
				"app_custom_policy_arn": "arn:aws:iam::123456789012:policy/RunsOnAppCustom",
			},
			expectPresent: []string{
				"aws_iam_role_policy_attachment.task_managed",
			},
		},
		{
			name: "RunnerCustomPolicy",
			overrides: map[string]any{
				"runner_custom_policy_arn": "arn:aws:iam::123456789012:policy/RunsOnRunnerCustom",
			},
			expectPresent: []string{
				"aws_iam_role_policy_attachment.ec2_custom[0]",
			},
		},
		{
			name: "BothCustomPolicies",
			overrides: map[string]any{
				"app_custom_policy_arn":    "arn:aws:iam::123456789012:policy/RunsOnAppCustom",
				"runner_custom_policy_arn": "arn:aws:iam::123456789012:policy/RunsOnRunnerCustom",
			},
			expectPresent: []string{
				"aws_iam_role_policy_attachment.task_managed",
				"aws_iam_role_policy_attachment.ec2_custom[0]",
			},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			plan := loadPlan(t, tc.overrides)

			for _, prefix := range tc.expectPresent {
				assert.Truef(t, hasResourceChangePrefix(plan, prefix),
					"Expected resource change matching %q in structured plan", prefix)
			}
			for _, prefix := range tc.expectAbsent {
				assert.Falsef(t, hasResourceChangePrefix(plan, prefix),
					"Did not expect resource change matching %q in structured plan", prefix)
			}
		})
	}
}

func TestPlanEmptyEbsEncryptionKeySkipsKmsLookup(t *testing.T) {
	t.Parallel()

	plan := loadPlan(t, map[string]any{
		"ebs_encryption_key_id": "",
	})

	assert.NotNil(t, plan, "plan should succeed when ebs_encryption_key_id is empty")
	assert.True(t, hasResourceChangePrefix(plan, "aws_iam_role_policy.task"),
		"task policy should still be planned when no explicit EBS KMS key is configured")
}

func TestPlanWarnsGhesManagedWafWithoutAcl(t *testing.T) {
	t.Parallel()

	opts := newPlanOptions(t, map[string]any{
		"enable_waf":            true,
		"github_enterprise_url": "https://ghe.example.com",
	})

	mustRunTerraformCommandQuietly(t, opts, "init")
	out := mustRunTerraformCommandQuietly(t, opts, "plan", "-input=false", "-lock=false")

	assert.Contains(t, out, "Check block assertion failed")
	assert.Contains(t, out, "public_ingress_web_acl_arn")
}

// TestPlanResourceCounts verifies the baseline deployment creates a reasonable number of resources.
func TestPlanResourceCounts(t *testing.T) {
	t.Parallel()

	plan := loadPlan(t, nil)
	createdCount := countResourceActions(plan, func(actions tfjson.Actions) bool {
		return actions.Create()
	})

	assert.GreaterOrEqual(t, createdCount, 30,
		"Baseline plan should create at least 30 resources, got %d", createdCount)

	t.Logf("Baseline plan creates %d resources", createdCount)
}
