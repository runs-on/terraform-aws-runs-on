package test

import (
	"encoding/json"
	"maps"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclparse"
	tfjson "github.com/hashicorp/terraform-json"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/zclconf/go-cty/cty"
)

var sharedPlanHarness struct {
	once       sync.Once
	root       string
	cleanup    func()
	env        map[string]string
	initOutput string
	initErr    error
}

func TestMain(m *testing.M) {
	code := m.Run()
	if sharedPlanHarness.cleanup != nil {
		sharedPlanHarness.cleanup()
	}
	os.Exit(code)
}

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

	terraformRoot := sharedPlanRoot(t)
	return &terraform.Options{
		TerraformDir:    terraformRoot,
		TerraformBinary: "tofu",
		Vars:            planVars(overrides),
		PlanFilePath:    filepath.Join(t.TempDir(), "plan.out"),
		NoColor:         true,
		EnvVars:         maps.Clone(sharedPlanHarness.env),
	}
}

func sharedPlanRoot(t *testing.T) string {
	t.Helper()

	sharedPlanHarness.once.Do(func() {
		sharedPlanHarness.root, sharedPlanHarness.cleanup = copyTerraformRootUnmanaged(t, "plan-harness")
		awsServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.Header().Set("Content-Type", "text/xml")
			_, _ = w.Write([]byte(`<?xml version="1.0" encoding="UTF-8"?>
<GetCallerIdentityResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">
  <GetCallerIdentityResult>
    <Arn>arn:aws:iam::123456789012:user/terraform-plan-test</Arn>
    <UserId>AIDATERRAFORMPLAN</UserId>
    <Account>123456789012</Account>
  </GetCallerIdentityResult>
  <ResponseMetadata><RequestId>00000000-0000-0000-0000-000000000000</RequestId></ResponseMetadata>
</GetCallerIdentityResponse>`))
		}))
		rootCleanup := sharedPlanHarness.cleanup
		sharedPlanHarness.cleanup = func() {
			awsServer.Close()
			rootCleanup()
		}
		// Plan-only tests need account and region facts, not live AWS access.
		// Keep that infrastructure detail behind the harness interface so every
		// caller gets deterministic credentials and a local STS adapter.
		sharedPlanHarness.env = map[string]string{
			"AWS_ACCESS_KEY_ID":         "test",
			"AWS_SECRET_ACCESS_KEY":     "test",
			"AWS_REGION":                "us-east-1",
			"AWS_DEFAULT_REGION":        "us-east-1",
			"AWS_EC2_METADATA_DISABLED": "true",
			"AWS_ENDPOINT_URL_STS":      awsServer.URL,
		}
		options := &terraform.Options{
			TerraformDir:    sharedPlanHarness.root,
			TerraformBinary: "tofu",
			NoColor:         true,
			EnvVars:         maps.Clone(sharedPlanHarness.env),
		}
		// Keep the pinned versions, but let init add this platform's package
		// hashes to the temporary lockfile before plans validate the unpacked
		// providers. The checked-in lockfile may have been created elsewhere.
		sharedPlanHarness.initOutput, sharedPlanHarness.initErr = runTerraformCommandQuietlyWithRetry(
			t,
			options,
			"init",
			"-backend=false",
			"-input=false",
		)
	})

	require.NoErrorf(t, sharedPlanHarness.initErr, "shared terraform init failed.\nCaptured output:\n%s", sharedPlanHarness.initOutput)
	return sharedPlanHarness.root
}

func loadPlan(t *testing.T, overrides map[string]any) *terraform.PlanStruct {
	t.Helper()

	options := newPlanOptions(t, overrides)
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

	// terraform.FormatArgs appends -var/-var-file to every command, but only
	// plan accepts them; init and show reject the flags outright. Strip vars
	// for non-plan commands while keeping the rest of the option formatting
	// (plan-file positional arg for show, -no-color, lock flags).
	formatOptions := options
	if len(args) > 0 && args[0] != "plan" {
		varsFree := *options
		varsFree.Vars = nil
		varsFree.VarFiles = nil
		varsFree.MixedVars = nil
		formatOptions = &varsFree
	}
	commandArgs := terraform.FormatArgs(formatOptions, args...)
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

func plannedResourceAfter(t *testing.T, plan *terraform.PlanStruct, address string) map[string]any {
	t.Helper()

	change := findResourceChange(plan, address)
	require.NotNilf(t, change, "expected resource change %q", address)
	require.NotNil(t, change.Change, "expected resource change details for %q", address)

	after, ok := change.Change.After.(map[string]any)
	require.Truef(t, ok, "expected %q after value to be an object", address)
	return after
}

func plannedPolicyDocument(t *testing.T, plan *terraform.PlanStruct, address string) map[string]any {
	t.Helper()

	after := plannedResourceAfter(t, plan, address)

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

func TestPlanTrimModulePath(t *testing.T) {
	t.Parallel()

	assert.Equal(t,
		"aws_lambda_function.github_waf_sync[0]",
		trimModulePath("module.control_plane.aws_lambda_function.github_waf_sync[0]"))
	assert.Equal(t,
		"aws_iam_role_policy_attachment.ec2_custom_additional[0]",
		trimModulePath("module.compute.aws_iam_role_policy_attachment.ec2_custom_additional[0]"))
	assert.Equal(t,
		"aws_efs_mount_target.az1[0]",
		trimModulePath("module.extras.aws_efs_mount_target.az1[0]"))
	assert.Equal(t,
		"aws_security_group.runners",
		trimModulePath("aws_security_group.runners"))
}

func TestPlanModuleManagedSSMAttachmentCanBeDisabled(t *testing.T) {
	t.Parallel()

	plan := loadPlan(t, map[string]any{"ssm_allowed": false})
	assert.False(t, hasResourceChangePrefix(plan, "module.compute.aws_iam_role_policy_attachment.ec2_ssm"))
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
				"aws_lambda_function.cache_credential_broker",
				"aws_iam_role_policy.cache_credential_broker_assume_runner",
			},
			expectAbsent: []string{
				"aws_secretsmanager_secret_version.runs_on_stack_config",
				// Account-wide API Gateway logging role; another stack would overwrite it.
				"aws_api_gateway_account",
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
			name: "PrivateModeOnlyAllowsEmptyPublicSubnets",
			overrides: map[string]any{
				"public_subnet_ids":  []string{},
				"private_mode":       "only",
				"private_subnet_ids": []string{"subnet-22222222"},
			},
		},
		{
			name: "PrivateModeOnlyAllowsEmptyPublicSubnetsWithEFS",
			overrides: map[string]any{
				"enable_efs":         true,
				"public_subnet_ids":  []string{},
				"private_mode":       "only",
				"private_subnet_ids": []string{"subnet-22222222"},
			},
			expectPresent: []string{
				"aws_efs_file_system.this_",
				"aws_efs_mount_target.az1[0]",
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
				"app_custom_policy_arns": []string{"arn:aws:iam::123456789012:policy/RunsOnAppCustom"},
			},
			expectPresent: []string{
				"aws_iam_role_policy_attachment.task_managed",
			},
		},
		{
			name: "RunnerCustomPolicy",
			overrides: map[string]any{
				"runner_custom_policy_arns": []string{"arn:aws:iam::123456789012:policy/RunsOnRunnerCustom"},
			},
			expectPresent: []string{
				"aws_iam_role_policy_attachment.ec2_custom_additional[0]",
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
				"app_custom_policy_arns":    []string{"arn:aws:iam::123456789012:policy/RunsOnAppCustom"},
				"runner_custom_policy_arns": []string{"arn:aws:iam::123456789012:policy/RunsOnRunnerCustom"},
			},
			expectPresent: []string{
				"aws_iam_role_policy_attachment.task_managed",
				"aws_iam_role_policy_attachment.ec2_custom_additional[0]",
			},
		},
		{
			name: "RunnerCustomPolicyWithBedrock",
			overrides: map[string]any{
				"runner_custom_policy_arns": []string{"arn:aws:iam::123456789012:policy/RunsOnRunnerCustom"},
				"enable_bedrock":            true,
			},
			expectPresent: []string{
				"aws_iam_role_policy_attachment.ec2_custom_additional[0]",
				"aws_iam_role_policy.ec2_bedrock_access[0]",
			},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
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

func TestPlanPermissionBoundaryAppliesToAllRoles(t *testing.T) {
	t.Parallel()

	const boundaryARN = "arn:aws:iam::123456789012:policy/RequiredBoundary"
	plan := loadPlan(t, map[string]any{
		"permission_boundary_arn": boundaryARN,
		"enable_waf":              true,
		"alert_slack_webhook_url": "https://hooks.slack.com/services/example",
	})

	roleCount := 0
	for address, change := range plan.ResourceChangesMap {
		if change == nil || change.Type != "aws_iam_role" {
			continue
		}
		roleCount++
		after, ok := change.Change.After.(map[string]any)
		require.Truef(t, ok, "expected %s after value to be an object", address)
		assert.Equalf(t, boundaryARN, after["permissions_boundary"],
			"%s should use the configured permissions boundary", address)
	}

	assert.GreaterOrEqual(t, roleCount, 12, "the all-role assertion should cover every current Flex stack IAM role")
}

// Fleet owns one scale-set session and a process-local pool publication
// fence, so ECS must stop the old controller before starting its replacement.
// The Fleet root is not planned here, so read the runtime module call instead.
func TestPlanFleetRunsOneControllerDuringDeployments(t *testing.T) {
	t.Parallel()

	file, diags := hclparse.NewParser().ParseHCLFile(filepath.Join("..", "..", "control_plane", "control_plane_fleet", "main.tf"))
	require.False(t, diags.HasErrors(), diags.Error())
	content, _, diags := file.Body.PartialContent(&hcl.BodySchema{
		Blocks: []hcl.BlockHeaderSchema{{Type: "module", LabelNames: []string{"name"}}},
	})
	require.False(t, diags.HasErrors(), diags.Error())

	for _, block := range content.Blocks {
		if block.Labels[0] != "runtime" {
			continue
		}
		attributes, diags := block.Body.JustAttributes()
		require.False(t, diags.HasErrors(), diags.Error())
		attribute, ok := attributes["deployment_maximum_percent"]
		require.True(t, ok, "Fleet runtime must set deployment_maximum_percent")
		value, diags := attribute.Expr.Value(nil)
		require.False(t, diags.HasErrors(), "deployment_maximum_percent must be a literal: %s", diags.Error())
		assert.True(t, value.Equals(cty.NumberIntVal(100)).True(), "deployment_maximum_percent = %s, want 100", value.GoString())
		return
	}
	t.Fatal("Fleet control plane has no runtime module")
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
