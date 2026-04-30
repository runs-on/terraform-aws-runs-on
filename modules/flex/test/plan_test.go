package test

import (
	"encoding/json"
	"maps"
	"os"
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

func readTerraformSource(t *testing.T, parts ...string) string {
	t.Helper()

	pathParts := append([]string{"..", "..", ".."}, parts...)
	content, err := os.ReadFile(filepath.Join(pathParts...))
	require.NoError(t, err)
	return string(content)
}

func readRepoSource(t *testing.T, parts ...string) string {
	t.Helper()

	pathParts := append([]string{"..", "..", "..", ".."}, parts...)
	content, err := os.ReadFile(filepath.Join(pathParts...))
	require.NoError(t, err)
	return string(content)
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

func findResourceChange(plan *terraform.PlanStruct, address string) *tfjson.ResourceChange {
	for actualAddress, change := range plan.ResourceChangesMap {
		if trimModulePath(actualAddress) == address {
			return change
		}
	}
	return nil
}

func plannedPolicyDocument(t *testing.T, plan *terraform.PlanStruct, address string) map[string]any {
	t.Helper()

	change := findResourceChange(plan, address)
	require.NotNilf(t, change, "expected resource change %q", address)
	require.NotNil(t, change.Change, "expected resource change details for %q", address)

	after, ok := change.Change.After.(map[string]any)
	require.Truef(t, ok, "expected %q after value to be an object", address)

	policyJSON, ok := after["policy"].(string)
	require.Truef(t, ok, "expected %q policy to be a JSON string", address)

	var policy map[string]any
	require.NoError(t, json.Unmarshal([]byte(policyJSON), &policy))
	return policy
}

func policyStatements(t *testing.T, policy map[string]any) []any {
	t.Helper()

	statements, ok := policy["Statement"].([]any)
	require.True(t, ok, "expected policy Statement to be an array")
	return statements
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

func TestStackConfigMaterializerSourceWiring(t *testing.T) {
	t.Parallel()

	secretsTF := readTerraformSource(t, "modules", "control_plane", "flex", "secrets.tf")
	mainTF := readTerraformSource(t, "modules", "control_plane", "flex", "main.tf")
	ingressTF := readTerraformSource(t, "modules", "control_plane", "flex", "ingress.tf")
	serviceTF := readTerraformSource(t, "modules", "control_plane", "flex", "service.tf")

	assert.NotContains(t, secretsTF, `resource "aws_secretsmanager_secret_version" "runs_on_stack_config"`)
	assert.Contains(t, secretsTF, `resource "aws_lambda_invocation" "stack_config_materializer"`)
	assert.Contains(t, secretsTF, "secretsmanager:PutSecretValue")

	assert.Contains(t, mainTF, "RUNS_ON_STACK_CONFIG_SECRET_ARN")
	assert.Contains(t, mainTF, "aws_secretsmanager_secret.runs_on_stack_config.arn")
	assert.Contains(t, mainTF, "RUNS_ON_STACK_CONFIG_SECRET_VERSION")
	assert.Contains(t, mainTF, "local.stack_config_secret_version")

	assert.Contains(t, ingressTF, "RUNS_ON_STACK_CONFIG_SECRET_VERSION")
	assert.Contains(t, ingressTF, "local.stack_config_secret_version")
	assert.Contains(t, serviceTF, "aws_lambda_invocation.stack_config_materializer")
}

func TestBedrockPolicySourceWiring(t *testing.T) {
	t.Parallel()

	iamTF := readTerraformSource(t, "modules", "runner", "compute", "iam.tf")

	assert.Contains(t, iamTF, `resource "aws_iam_role_policy" "ec2_bedrock_access"`)
	assert.Contains(t, iamTF, `count = var.enable_bedrock ? 1 : 0`)
	assert.Contains(t, iamTF, `"bedrock:InvokeModel"`)
	assert.Contains(t, iamTF, `"bedrock:InvokeModelWithResponseStream"`)
	assert.Contains(t, iamTF, `"bedrock:ListInferenceProfiles"`)
	assert.Contains(t, iamTF, `"arn:aws:bedrock:*:*:foundation-model/*"`)
	assert.Contains(t, iamTF, `"arn:aws:bedrock:*:*:inference-profile/*"`)
	assert.Contains(t, iamTF, `"arn:aws:bedrock:*:*:application-inference-profile/*"`)
}

func TestRuntimeECSServicePropagatesTagsToTasks(t *testing.T) {
	t.Parallel()

	runtimeTF := readTerraformSource(t, "modules", "control_plane", "runtime", "main.tf")

	assert.Contains(t, runtimeTF, `resource "aws_ecs_service" "this"`)
	assert.Contains(t, runtimeTF, `propagate_tags   = "SERVICE"`)
	assert.Contains(t, runtimeTF, `enable_ecs_managed_tags = true`)
}

func TestPublicIngressDeploymentAvoidsAdminRouteDestroyCycle(t *testing.T) {
	t.Parallel()

	ingressTF := readTerraformSource(t, "modules", "control_plane", "flex", "ingress.tf")
	_, afterDeployment, ok := strings.Cut(ingressTF, `resource "aws_api_gateway_deployment" "public_ingress"`)
	require.True(t, ok, "public ingress deployment resource should exist")

	deploymentBody, _, ok := strings.Cut(afterDeployment, `resource "aws_api_gateway_stage" "public_ingress"`)
	require.True(t, ok, "public ingress stage should follow the deployment resource")

	assert.NotContains(t, deploymentBody, "depends_on = [")
	assert.Contains(t, deploymentBody, "aws_api_gateway_integration.github_webhooks.id")

	for _, guardedAdminFingerprint := range []string{
		`local.admin_routes_enabled ? aws_api_gateway_integration.root[0].id : ""`,
		`local.admin_routes_enabled ? aws_api_gateway_integration.setup[0].id : ""`,
		`local.admin_routes_enabled ? aws_api_gateway_integration.setup_proxy[0].id : ""`,
		`local.admin_routes_enabled ? aws_api_gateway_integration.readyz[0].id : ""`,
		`local.admin_routes_enabled ? aws_lambda_function.github_apps_setup[0].source_code_hash : ""`,
	} {
		assert.Contains(t, deploymentBody, guardedAdminFingerprint)
	}
}

func TestGitHubRunnerCacheRefreshSeedSourceWiring(t *testing.T) {
	t.Parallel()

	githubRunnerCacheTF := readTerraformSource(t, "modules", "control_plane", "flex", "github_runner_cache.tf")

	assert.Contains(t, githubRunnerCacheTF, `resource "aws_lambda_invocation" "github_runner_cache_refresh_seed"`)
	assert.Contains(t, githubRunnerCacheTF, "function_name = aws_lambda_function.github_runner_cache_refresh.function_name")
	assert.Contains(t, githubRunnerCacheTF, "bucket = var.extras.cache.bucket_name")
	assert.NotContains(t, githubRunnerCacheTF, "lifecycle_scope")
	assert.NotContains(t, githubRunnerCacheTF, "triggers =")
}

func TestCloudFormationEphemeralRegistryUsesGeneratedNameAndStackTags(t *testing.T) {
	t.Parallel()

	template := readRepoSource(t, "cloudformation", "template.yaml")
	_, afterResource, ok := strings.Cut(template, "  EphemeralRegistry:")
	require.True(t, ok, "EphemeralRegistry resource should exist")
	resourceBody, _, ok := strings.Cut(afterResource, "  # --- End Ephemeral Registry Resources ---")
	require.True(t, ok, "EphemeralRegistry resource block should be delimited")

	assert.NotContains(t, resourceBody, "RepositoryName")
	assert.Contains(t, resourceBody, "Tags:")
	assert.Contains(t, resourceBody, "Key: !Ref CostAllocationTag")
	assert.Contains(t, resourceBody, "Key: runs-on-stack-name")
	assert.Contains(t, resourceBody, "Value: !Ref AWS::StackName")
}

func TestTerraformEphemeralRegistryUsesGeneratedNameAndStackTags(t *testing.T) {
	t.Parallel()

	ecrTF := readTerraformSource(t, "modules", "runner", "extras", "ecr.tf")

	assert.Contains(t, ecrTF, `resource "random_id" "ephemeral_registry"`)
	assert.Contains(t, ecrTF, `resource "aws_ecr_repository" "ephemeral"`)
	assert.Contains(t, ecrTF, `ecr_repository_name_generated = var.enable_ecr ? "runs-on-${random_id.ephemeral_registry[0].hex}-ephemeral-registry" : ""`)
	assert.Contains(t, ecrTF, `name                 = local.ecr_repository_name_generated`)
	assert.Contains(t, ecrTF, `force_delete         = true`)
	assert.NotContains(t, ecrTF, `name                 = "${var.stack_name}-ephemeral-registry"`)
	assert.NotContains(t, ecrTF, `prevent_destroy = true`)
	assert.NotContains(t, ecrTF, `ephemeral_protected`)
	assert.NotContains(t, ecrTF, `ephemeral_unprotected`)
	assert.NotContains(t, ecrTF, `force_delete_ecr`)
	assert.Contains(t, ecrTF, `Name = "${var.stack_name}-ephemeral-registry"`)

	variablesTF := readTerraformSource(t, "modules", "flex", "variables.tf")
	assert.NotContains(t, variablesTF, `variable "force_delete_ecr"`)
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
				"aws_lambda_function.stack_config_materializer",
				"aws_lambda_invocation.stack_config_materializer",
				"aws_lambda_function.github_runner_cache_refresh",
				"aws_lambda_invocation.github_runner_cache_refresh_seed",
				"aws_scheduler_schedule.github_runner_cache_refresh",
			},
			expectAbsent: []string{
				"aws_secretsmanager_secret_version.runs_on_stack_config",
				"aws_efs_file_system",
				"aws_ecr_repository",
				"aws_iam_role_policy.ec2_bedrock_access",
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
				"aws_ecr_repository.ephemeral",
			},
		},
		{
			name: "ECROnly",
			overrides: map[string]any{
				"enable_ecr": true,
			},
			expectPresent: []string{
				"random_id.ephemeral_registry",
				"aws_ecr_repository.ephemeral",
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
				"random_id.ephemeral_registry",
				"aws_ecr_repository.ephemeral",
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
			name: "BedrockEnabled",
			overrides: map[string]any{
				"enable_bedrock": true,
			},
			expectPresent: []string{
				"aws_iam_role_policy.ec2_bedrock_access[0]",
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
		{
			name: "RunnerCustomPolicyWithBedrock",
			overrides: map[string]any{
				"runner_custom_policy_arn": "arn:aws:iam::123456789012:policy/RunsOnRunnerCustom",
				"enable_bedrock":           true,
			},
			expectPresent: []string{
				"aws_iam_role_policy_attachment.ec2_custom[0]",
				"aws_iam_role_policy.ec2_bedrock_access[0]",
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

func TestPlanOtelHeadersGrantExecutionRoleSSMAccess(t *testing.T) {
	t.Parallel()

	plan := loadPlan(t, map[string]any{
		"otel_exporter_headers": "x-signoz-ingestion-key=test",
	})

	assert.True(t, hasResourceChangePrefix(plan, "aws_ssm_parameter.otel_exporter_headers"),
		"OTEL headers should be stored as an SSM SecureString when configured")

	policy := plannedPolicyDocument(t, plan, "aws_iam_role_policy.execution_extra[0]")
	statements := policyStatements(t, policy)
	require.Len(t, statements, 1)

	statement, ok := statements[0].(map[string]any)
	require.True(t, ok, "expected execution role policy statement to be an object")
	assert.Equal(t, "Allow", statement["Effect"])
	assert.Equal(t, []any{"ssm:GetParameters"}, statement["Action"])

	resource, ok := statement["Resource"].(string)
	require.True(t, ok, "expected execution role policy resource to be a string")
	assert.Contains(t, resource, ":ssm:")
	assert.True(t, strings.HasSuffix(resource, ":parameter/test-plan/secrets/otel-exporter-headers"),
		"expected execution role policy to be scoped to the OTEL headers parameter, got %q", resource)
}

func TestPlanWithoutOtelHeadersSkipsExecutionRoleSSMPolicy(t *testing.T) {
	t.Parallel()

	plan := loadPlan(t, nil)

	assert.False(t, hasResourceChangePrefix(plan, "aws_iam_role_policy.execution_extra"),
		"baseline plan should not add an extra execution-role policy when no ECS secret is configured")
	assert.False(t, hasResourceChangePrefix(plan, "aws_ssm_parameter.otel_exporter_headers"),
		"baseline plan should not create the OTEL headers parameter")
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
