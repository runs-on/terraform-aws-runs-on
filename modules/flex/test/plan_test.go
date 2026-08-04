package test

import (
	"archive/zip"
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
	tfjson "github.com/hashicorp/terraform-json"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
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
	mustRunTerraformCommandQuietly(t, options, "plan", "-input=false", "-lock=false")
	showOut := mustRunTerraformCommandQuietly(t, options, "show", "-json")

	plan, err := terraform.ParsePlanJSON(showOut)
	require.NoError(t, err, "terraform show output should parse as a structured plan")
	return plan
}

func requirePlanFailure(t *testing.T, overrides map[string]any, expectedSubstrings ...string) {
	t.Helper()

	options := newPlanOptions(t, overrides)
	out, err := runTerraformCommandQuietly(t, options, "plan", "-input=false", "-lock=false")
	require.Errorf(t, err, "terraform plan unexpectedly succeeded.\nCaptured output:\n%s", out)
	for _, expected := range expectedSubstrings {
		assert.Contains(t, out, expected)
	}
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

func TestPlanSourceTerraformLambdaArtifactsAreBundled(t *testing.T) {
	t.Parallel()

	for _, parts := range [][]string{
		{"modules", "control_plane", "alerts", "main.tf"},
		{"modules", "control_plane", "fleet", "cache_credential_broker.tf"},
		{"modules", "control_plane", "fleet", "job_diagnostics_resolver.tf"},
		{"modules", "control_plane", "fleet", "main.tf"},
		{"modules", "control_plane", "fleet", "secrets.tf"},
		{"modules", "control_plane", "flex", "cache_credential_broker.tf"},
		{"modules", "control_plane", "flex", "github_runner_cache.tf"},
		{"modules", "control_plane", "flex", "ingress.tf"},
		{"modules", "control_plane", "flex", "job_diagnostics_resolver.tf"},
		{"modules", "control_plane", "flex", "main.tf"},
		{"modules", "control_plane", "flex", "secrets.tf"},
		{"modules", "control_plane", "flex", "waf.tf"},
	} {
		source := readTerraformSource(t, parts...)
		path := strings.Join(parts, "/")
		assert.NotContains(t, source, `data "archive_file"`, path)
		assert.NotContains(t, source, `data.archive_file`, path)
		assert.NotContains(t, source, `hashicorp/archive`, path)
		assert.NotContains(t, source, `path.root}/.terraform`, path)
		assert.NotContains(t, source, `path.cwd`, path)
	}

	for _, artifact := range []struct {
		name      string
		zipEntry  string
		reference string
	}{
		{name: "cache-credential-broker.zip", zipEntry: "index.js", reference: "cache credential broker"},
		{name: "fleet-config-materializer.zip", zipEntry: "index.py", reference: "fleet/secrets.tf"},
		{name: "github-apps-setup.zip", zipEntry: "index.js", reference: "flex/ingress.tf"},
		{name: "github-runner-cache-refresh.zip", zipEntry: "index.js", reference: "flex/github_runner_cache.tf"},
		{name: "github-waf-sync.zip", zipEntry: "index.js", reference: "flex/waf.tf"},
		{name: "job-diagnostics-resolver.zip", zipEntry: "index.js", reference: "flex/fleet job diagnostics"},
		{name: "public-ingress.zip", zipEntry: "index.js", reference: "flex/ingress.tf"},
		{name: "slack-webhook.zip", zipEntry: "index.py", reference: "alerts/main.tf"},
		{name: "stack-config-materializer.zip", zipEntry: "index.py", reference: "flex/secrets.tf"},
	} {
		artifactPath := filepath.Join("..", "..", "..", "lambdas", "dist", artifact.name)
		archive, err := zip.OpenReader(artifactPath)
		require.NoErrorf(t, err, "%s should exist for %s", artifact.name, artifact.reference)
		defer archive.Close()
		require.Len(t, archive.File, 1, artifact.name)
		assert.Equal(t, artifact.zipEntry, archive.File[0].Name, artifact.name)
	}

	flexMain := readTerraformSource(t, "modules", "control_plane", "flex", "main.tf")
	fleetMain := readTerraformSource(t, "modules", "control_plane", "fleet", "main.tf")
	alertsMain := readTerraformSource(t, "modules", "control_plane", "alerts", "main.tf")
	assert.Contains(t, flexMain, `lambda_artifact_dir`)
	assert.Contains(t, fleetMain, `lambda_artifact_dir`)
	assert.Contains(t, alertsMain, `lambda_artifact_dir`)
}

func TestPlanSourceStackConfigMaterializerWiring(t *testing.T) {
	t.Parallel()

	secretsTF := readTerraformSource(t, "modules", "control_plane", "flex", "secrets.tf")
	mainTF := readTerraformSource(t, "modules", "control_plane", "flex", "main.tf")
	ingressTF := readTerraformSource(t, "modules", "control_plane", "flex", "ingress.tf")
	resolverTF := readTerraformSource(t, "modules", "control_plane", "flex", "job_diagnostics_resolver.tf")
	serviceTF := readTerraformSource(t, "modules", "control_plane", "flex", "service.tf")

	assert.NotContains(t, secretsTF, `resource "aws_secretsmanager_secret_version" "runs_on_stack_config"`)
	assert.Contains(t, secretsTF, `resource "aws_lambda_invocation" "stack_config_materializer"`)
	assert.Contains(t, secretsTF, "secretsmanager:PutSecretValue")

	assert.Contains(t, mainTF, "RUNS_ON_STACK_CONFIG_SECRET_ARN")
	assert.Contains(t, mainTF, "aws_secretsmanager_secret.runs_on_stack_config.arn")
	assert.Contains(t, mainTF, "RUNS_ON_STACK_CONFIG_SECRET_VERSION")
	assert.Contains(t, mainTF, "local.stack_config_secret_version")
	assert.Contains(t, mainTF, `DeploymentMethod                   = "terraform"`)

	assert.Contains(t, ingressTF, "RUNS_ON_STACK_CONFIG_SECRET_VERSION")
	assert.Contains(t, ingressTF, "local.stack_config_secret_version")
	assert.Contains(t, resolverTF, "RUNS_ON_STACK_CONFIG_SECRET_VERSION")
	assert.Contains(t, resolverTF, "local.stack_config_secret_version")
	assert.Contains(t, serviceTF, "aws_lambda_invocation.stack_config_materializer")
}

func TestPlanSourceBedrockPolicyWiring(t *testing.T) {
	t.Parallel()

	iamTF := readTerraformSource(t, "modules", "runner", "compute", "iam.tf")

	assert.Contains(t, iamTF, `resource "aws_iam_role_policy" "ec2_bedrock_access"`)
	assert.Contains(t, iamTF, `count = var.enable_bedrock ? 1 : 0`)
	assert.Contains(t, iamTF, `"bedrock:InvokeModel"`)
	assert.Contains(t, iamTF, `"bedrock:InvokeModelWithResponseStream"`)
	assert.Contains(t, iamTF, `"bedrock:ListInferenceProfiles"`)
	assert.Contains(t, iamTF, `"arn:${local.partition}:bedrock:*:*:foundation-model/*"`)
	assert.Contains(t, iamTF, `"arn:${local.partition}:bedrock:*:*:inference-profile/*"`)
	assert.Contains(t, iamTF, `"arn:${local.partition}:bedrock:*:*:application-inference-profile/*"`)
}

func TestPlanSourceRuntimeECSServicePropagatesTagsToTasks(t *testing.T) {
	t.Parallel()

	runtimeTF := readTerraformSource(t, "modules", "control_plane", "runtime", "main.tf")

	assert.Contains(t, runtimeTF, `resource "aws_ecs_service" "this"`)
	assert.Contains(t, runtimeTF, `propagate_tags   = "SERVICE"`)
	assert.Contains(t, runtimeTF, `enable_ecs_managed_tags = true`)
}

func TestPlanSourceFleetConfigMaterializerWiring(t *testing.T) {
	t.Parallel()

	mainTF := readTerraformSource(t, "modules", "control_plane", "fleet", "main.tf")
	resolverTF := readTerraformSource(t, "modules", "control_plane", "fleet", "job_diagnostics_resolver.tf")
	secretsTF := readTerraformSource(t, "modules", "control_plane", "fleet", "secrets.tf")

	assert.NotContains(t, mainTF, `resource "aws_secretsmanager_secret_version" "config"`)
	assert.NotContains(t, secretsTF, `resource "aws_secretsmanager_secret_version" "config"`)
	assert.Contains(t, mainTF, "from = aws_secretsmanager_secret_version.config")
	assert.Contains(t, secretsTF, `resource "aws_lambda_invocation" "config_materializer"`)
	assert.Contains(t, secretsTF, "secretsmanager:PutSecretValue")

	assert.Contains(t, mainTF, "RUNS_ON_FLEET_CONFIG_SECRET_ARN")
	assert.Contains(t, mainTF, "aws_secretsmanager_secret.config.arn")
	assert.Contains(t, mainTF, "RUNS_ON_FLEET_CONFIG_SECRET_VERSION")
	assert.Contains(t, mainTF, "local.config_secret_version")
	assert.Contains(t, resolverTF, "RUNS_ON_FLEET_CONFIG_SECRET_VERSION")
	assert.Contains(t, resolverTF, "local.config_secret_version")
	assert.Contains(t, mainTF, "aws_lambda_invocation.config_materializer")
	assert.Contains(t, mainTF, `deployment_method                      = "terraform"`)
}

func TestPlanSourceFleetRunsOneControllerDuringDeployments(t *testing.T) {
	t.Parallel()

	fleetTF := readTerraformSource(t, "modules", "control_plane", "fleet", "main.tf")
	runtimeTF := readTerraformSource(t, "modules", "control_plane", "runtime", "main.tf")

	assert.Contains(t, fleetTF, "deployment_maximum_percent = 100")
	assert.Contains(t, runtimeTF, `availability_zone_rebalancing = var.deployment_maximum_percent <= 100 ? "DISABLED" : null`)
}

func TestPlanSourceFleetCIStackKeepsPrivateSubnetsStable(t *testing.T) {
	t.Parallel()

	mainTF := readRepoSource(t, "stacks", "tf", "modules", "fleet-stack", "main.tf")

	assert.Contains(t, mainTF, "private_subnets = local.network.private_subnet_cidrs")
	assert.Contains(t, mainTF, "enable_nat_gateway = local.private_mode_enabled")
	assert.NotContains(t, mainTF, "private_subnets = (\n    local.private_mode_enabled")
}

func TestPlanSourceFleetCIDefaultFleetEnablesRequiredExtras(t *testing.T) {
	t.Parallel()

	mainTF := readRepoSource(t, "stacks", "tf", "modules", "fleet-stack", "main.tf")

	_, afterSnapshotRunner, ok := strings.Cut(mainTF, "snap-x64 = {")
	require.True(t, ok, "snap-x64 runner should be configured")

	snapshotRunner, _, ok := strings.Cut(afterSnapshotRunner, "\n  }\n\n  fleets = {")
	require.True(t, ok, "snap-x64 runner block should end before fleets")

	assert.Contains(t, snapshotRunner, `extras = ["s3-cache", "ecr-pull-through"]`)

	_, afterRunner, ok := strings.Cut(mainTF, "small-x64 = {")
	require.True(t, ok, "small-x64 runner should be configured")

	smallRunner, _, ok := strings.Cut(afterRunner, "fast-x64 = {")
	require.True(t, ok, "small-x64 runner block should end before fast-x64")

	assert.Contains(t, smallRunner, `extras = ["s3-cache", "ecr-pull-through", "otel"]`)
}

func TestPlanSourceFleetPrivateDeployUsesPrivateOnlyMode(t *testing.T) {
	t.Parallel()

	workflow := readRepoSource(t, ".github", "workflows", "core-deploy-terraform.yml")

	_, afterPrivateTrue, ok := strings.Cut(workflow, "private_true)")
	require.True(t, ok, "private_true stack variant should be handled")

	privateTrueCase, _, ok := strings.Cut(afterPrivateTrue, ";;")
	require.True(t, ok, "private_true stack variant should terminate")

	assert.Contains(t, privateTrueCase, `private_mode="only"`)
	assert.NotContains(t, privateTrueCase, `private_mode="true"`)
}

func TestPlanSourceRuntimeWaitsForECSServiceSteadyState(t *testing.T) {
	t.Parallel()

	mainTF := readTerraformSource(t, "modules", "control_plane", "runtime", "main.tf")
	_, afterService, ok := strings.Cut(mainTF, `resource "aws_ecs_service" "this"`)
	require.True(t, ok, "runtime ECS service should exist")

	assert.Contains(t, afterService, "wait_for_steady_state = true")
}

func TestPlanSourcePublicIngressDeploymentAvoidsAdminRouteDestroyCycle(t *testing.T) {
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
	assert.Contains(t, githubRunnerCacheTF, "triggers =")
	assert.Contains(t, githubRunnerCacheTF, "lambda_version = aws_lambda_function.github_runner_cache_refresh.source_code_hash")
}

func TestPlanSourceCustomPolicyWiring(t *testing.T) {
	t.Parallel()

	mainTF := readTerraformSource(t, "modules", "flex", "main.tf")
	fleetMainTF := readTerraformSource(t, "modules", "fleet", "main.tf")
	serviceTF := readTerraformSource(t, "modules", "control_plane", "flex", "service.tf")

	// Regexp rather than Contains: the sticky-disk isolation flags widen the
	// compute block's argument alignment, so exact spacing would be brittle.
	assert.Regexp(t, `custom_policy_arns\s+= var\.app_custom_policy_arns`, mainTF)
	assert.Regexp(t, `runner_custom_policy_arns\s+= var\.runner_custom_policy_arns`, mainTF)
	assert.Regexp(t, `runner_custom_policy_arns\s+= var\.runner_custom_policy_arns`, fleetMainTF)
	assert.Contains(t, serviceTF, "task_role_managed_policy_arns   = compact(local.runtime.custom_policy_arns)")
}

func TestCacheCredentialBrokerWiring(t *testing.T) {
	t.Parallel()

	brokerTF := readTerraformSource(t, "modules", "control_plane", "flex", "cache_credential_broker.tf")
	fleetBrokerTF := readTerraformSource(t, "modules", "control_plane", "fleet", "cache_credential_broker.tf")
	fleetMainTF := readTerraformSource(t, "modules", "control_plane", "fleet", "main.tf")
	computeIAM := readTerraformSource(t, "modules", "runner", "compute", "iam.tf")
	extrasS3 := readTerraformSource(t, "modules", "runner", "extras", "s3.tf")
	cloudFormation := readRepoSource(t, "cloudformation", "template.yaml")
	oldScopedPrefix := "cache/" + "v1"

	assert.Contains(t, brokerTF, `resource "aws_lambda_function" "cache_credential_broker"`)
	assert.Contains(t, brokerTF, `function_name = "${var.stack_name}-cache-broker"`)
	assert.NotContains(t, brokerTF, `resource "aws_iam_role" "cache_job"`)
	assert.NotContains(t, brokerTF, `resource "aws_iam_policy" "cache_credential_broker_base_session"`)
	assert.NotContains(t, brokerTF, `BASE_SESSION_POLICY`)
	assert.NotContains(t, brokerTF, `local.cache_credential_broker_base_session_policy`)
	assert.Contains(t, brokerTF, `GITHUB_ENTERPRISE_URL`)
	assert.Contains(t, brokerTF, `GITHUB_TOKEN_ISSUER`)
	assert.Contains(t, brokerTF, `RunsOnCacheCredentialBrokerReadJwks`)
	assert.Contains(t, brokerTF, `agents/github-jwks.json`)
	assert.Contains(t, brokerTF, `RUNNER_ROLE_ARN`)
	assert.NotContains(t, brokerTF, `runner-identity.json`)
	assert.Contains(t, brokerTF, `s3:GetObject`)
	assert.Contains(t, brokerTF, `sts:TagSession`)
	assert.Contains(t, brokerTF, `aws:RequestTag/runs-on-cache-brokered`)
	assert.Contains(t, brokerTF, `aws:RequestTag/runs-on-cache-repository`)
	assert.NotContains(t, brokerTF, "/"+oldScopedPrefix+"/*")
	assert.Contains(t, fleetBrokerTF, `resource "aws_lambda_function" "cache_credential_broker"`)
	assert.Contains(t, fleetBrokerTF, `function_name = "${var.stack_name}-cache-broker"`)
	assert.NotContains(t, fleetBrokerTF, `local.cache_credential_broker_base_session_policy`)
	assert.Contains(t, fleetBrokerTF, `RUNNER_ROLE_ARN`)
	assert.Contains(t, fleetBrokerTF, `GITHUB_ENTERPRISE_URL`)
	assert.Contains(t, fleetBrokerTF, `GITHUB_TOKEN_ISSUER`)
	assert.Contains(t, fleetBrokerTF, `agents/github-jwks.json`)
	assert.NotContains(t, fleetBrokerTF, `runner-identity.json`)
	assert.Contains(t, fleetBrokerTF, `sts:TagSession`)
	assert.Contains(t, fleetMainTF, `cache_credential_broker_function_name  = var.enable_cache_isolation ? aws_lambda_function.cache_credential_broker.function_name : ""`)
	// Broker resources are always created; enable_cache_isolation only decides
	// whether runners receive the broker function name. Direct cache/* access
	// remains available independently of Magic Cache isolation.
	assert.NotContains(t, brokerTF, `count = var.enable_cache_isolation ? 1 : 0`)
	assert.NotContains(t, fleetBrokerTF, `count = var.enable_cache_isolation ? 1 : 0`)
	assert.Contains(t, brokerTF, `role          = aws_iam_role.cache_credential_broker.arn`)
	assert.Contains(t, fleetBrokerTF, `role          = aws_iam_role.cache_credential_broker.arn`)
	assert.Contains(t, computeIAM, `"lambda:InvokeFunction"`)
	assert.Contains(t, computeIAM, `function:${var.stack_name}-cache-broker`)
	assert.Contains(t, computeIAM, `"${var.extras.cache.bucket_arn}/scoped-cache/*"`)
	assert.NotContains(t, computeIAM, `/cache/shared/*`)
	assert.Contains(t, computeIAM, `aws:PrincipalTag/runs-on-cache-brokered`)
	assert.Contains(t, computeIAM, `aws:PrincipalArn`)
	assert.Contains(t, computeIAM, `arn:${local.partition}:iam::${var.account_id}:root`)
	assert.Contains(t, computeIAM, `sts:TagSession`)
	assert.NotContains(t, computeIAM, `if !var.enable_cache_isolation`)
	assert.Contains(t, computeIAM, `"${var.extras.cache.bucket_arn}/cache/*"`)
	// Legacy EBS snapshot policies are removed under sticky-disk isolation.
	assert.Contains(t, computeIAM, `count = var.enable_stickydisk_isolation ? 0 : 1`)
	assert.NotContains(t, extrasS3, `DenyRawInstanceRoleCacheAccess`)
	assert.NotContains(t, extrasS3, `DenyRawInstanceRoleCacheList`)
	assert.NotContains(t, extrasS3, "/"+oldScopedPrefix+"/*")
	assert.Contains(t, cloudFormation, `function:${AWS::StackName}-cache-broker`)
	assert.Contains(t, cloudFormation, `/scoped-cache/*`)
	assert.Contains(t, cloudFormation, `agents/github-jwks.json`)
	assert.NotContains(t, cloudFormation, `/cache/shared/*`)
	assert.NotContains(t, cloudFormation, `RunsOnCacheCredentialBrokerBaseSessionPolicy`)
	assert.NotContains(t, cloudFormation, `BASE_SESSION_POLICY`)
	assert.NotContains(t, cloudFormation, `Fn::ToJsonString`)
	assert.Contains(t, cloudFormation, `RUNNER_ROLE_ARN`)
	assert.Contains(t, cloudFormation, `GITHUB_ENTERPRISE_URL`)
	assert.Contains(t, cloudFormation, `GITHUB_TOKEN_ISSUER`)
	assert.NotContains(t, cloudFormation, `RunsOnCacheCredentialBrokerReadRunnerIdentityPolicy`)
	assert.NotContains(t, cloudFormation, `/runners/*/runner-identity.json`)
	assert.Contains(t, cloudFormation, `runs-on-cache-brokered`)
	assert.Contains(t, cloudFormation, `runs-on-cache-repository`)
	assert.NotContains(t, cloudFormation, `arn:${AWS::Partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole`)
	assert.NotContains(t, cloudFormation, "/"+oldScopedPrefix+"/*")
	// Magic Cache isolation is opt-in, but direct cache/* access is unconditional
	// and therefore survives both EnableCacheIsolation parameter values.
	assert.Contains(t, cloudFormation, `EnableCacheIsolation:`)
	assert.Contains(t, cloudFormation, `CacheIsolationEnabled: !Equals [!Ref EnableCacheIsolation, "true"]`)
	assert.NotContains(t, cloudFormation, `CacheIsolationDisabled:`)
	assert.NotContains(t, cloudFormation, "RunsOnCacheCredentialBrokerRole:\n    Type: AWS::IAM::Role\n    Condition: CacheIsolationEnabled")
	assert.NotContains(t, cloudFormation, "RunsOnCacheCredentialBrokerAssumeRunnerPolicy:\n    Type: AWS::IAM::Policy\n    Condition: CacheIsolationEnabled")
	assert.NotContains(t, cloudFormation, "RunsOnCacheCredentialBrokerReadJwksPolicy:\n    Type: AWS::IAM::Policy\n    Condition: CacheIsolationEnabled")
	assert.NotContains(t, cloudFormation, "RunsOnCacheCredentialBrokerFunction:\n    Type: AWS::Lambda::Function\n    Condition: CacheIsolationEnabled")
	assert.Contains(t, cloudFormation, `CacheCredentialBrokerFunctionName: !If [CacheIsolationEnabled, !Ref RunsOnCacheCredentialBrokerFunction, ""]`)
	assert.Contains(t, cloudFormation, `EnableStickyDiskIsolation:`)
	assert.Contains(t, cloudFormation, `StickyDiskIsolationDisabled: !Equals [!Ref EnableStickyDiskIsolation, "false"]`)
	assert.Contains(t, cloudFormation, `- StickyDiskIsolationDisabled`)
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

func TestPlanSourceCloudFormationStackConfigUsesDeploymentMethod(t *testing.T) {
	t.Parallel()

	template := readRepoSource(t, "cloudformation", "template.yaml")

	assert.Contains(t, template, `DeploymentMethod: "cloudformation"`)
	assert.NotContains(t, template, "InfrastructureSource")
}

func TestPlanSourceCloudFormationAutoExtendsDiagnosticsMatchRuntimeSentinel(t *testing.T) {
	t.Parallel()

	template := readRepoSource(t, "cloudformation", "template.yaml")

	assert.Contains(t, template, `RunnerConfigAutoExtendsEnabled: !And [!Not [!Equals [!Ref RunnerConfigAutoExtendsFrom, ""]], !Not [!Equals [!Ref RunnerConfigAutoExtendsFrom, "."]]]`)
	assert.Contains(t, template, `config_auto_extends_enabled: !If [RunnerConfigAutoExtendsEnabled, true, false]`)
}

func TestPlanSourceCloudFormationDiagnosticsAvoidEncryptionAssumptions(t *testing.T) {
	t.Parallel()

	template := readRepoSource(t, "cloudformation", "template.yaml")

	assert.Contains(t, template, `ebs_encryption_mode: !If [HasEncryptEbs, "aws-managed", "unspecified"]`)
}

func TestPlanSourceCloudFormationValidatesDiagnosticHeaderInput(t *testing.T) {
	t.Parallel()

	template := readRepoSource(t, "cloudformation", "template.yaml")

	assert.Contains(t, template, `must be empty or contain comma-separated key=value pairs with non-empty keys and values`)
}

func TestPlanSourceCloudFormationCostReportSchedules(t *testing.T) {
	t.Parallel()

	template := readRepoSource(t, "cloudformation", "template.yaml")
	assert.Contains(t, template, `Default: "daily"`)
	assert.Contains(t, template, `- "no"`)
	assert.Contains(t, template, `- "daily"`)
	assert.Contains(t, template, `- "weekly"`)
	assert.Contains(t, template, `- "monthly"`)
	assert.Contains(t, template, `CostReportsEnabled: !Not [!Equals [!Ref CostReportsEnabled, "no"]]`)
	assert.Contains(t, template, `ScheduleExpression: !FindInMap [CostReportSchedule, !Ref CostReportsEnabled, Expression]`)
	assert.Contains(t, template, `weekly:`)
	assert.Contains(t, template, `Expression: "cron(5 0 ? * MON *)"`)
	assert.Contains(t, template, `monthly:`)
	assert.Contains(t, template, `Expression: "cron(5 0 1 * ? *)"`)
	assert.Contains(t, template, `CostReportsEnabled: !If [CostReportsEnabled, "true", "false"]`)

	_, afterResource, ok := strings.Cut(template, "  SchedulerCostAllocationTag:")
	require.True(t, ok, "SchedulerCostAllocationTag resource should exist")
	resourceBody, _, ok := strings.Cut(afterResource, "  RunsOnGitHubRunnerCacheRefreshSchedule:")
	require.True(t, ok, "SchedulerCostAllocationTag resource block should be delimited")

	assert.Contains(t, resourceBody, "Condition: CostReportsEnabled")
	assert.Contains(t, resourceBody, `Input: '{"detail-type":"RunsOn Cost Allocation Tag"}'`)
}

func TestPlanSourceTerraformEphemeralRegistryUsesGeneratedNameAndStackTags(t *testing.T) {
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
				"aws_lambda_function.cache_credential_broker",
				"aws_iam_role_policy.cache_credential_broker_assume_runner",
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

func TestPlanRejectsEmptyPublicSubnetsUnlessPrivateOnly(t *testing.T) {
	t.Parallel()

	for _, privateMode := range []string{"false", "true", "always"} {
		t.Run(privateMode, func(t *testing.T) {
			t.Parallel()
			overrides := map[string]any{
				"public_subnet_ids": []string{},
				"private_mode":      privateMode,
			}
			if privateMode != "false" {
				overrides["private_subnet_ids"] = []string{"subnet-22222222"}
			}

			requirePlanFailure(t, overrides,
				"At least one public subnet ID is required unless private_mode is \"only\".")
		})
	}
}

func TestPlanEFSUsesPrivateSubnetsWhenConfigured(t *testing.T) {
	t.Parallel()

	plan := loadPlan(t, map[string]any{
		"enable_efs":         true,
		"public_subnet_ids":  []string{"subnet-11111111"},
		"private_mode":       "true",
		"private_subnet_ids": []string{"subnet-22222222"},
	})

	mountTarget := plannedResourceAfter(t, plan, "aws_efs_mount_target.az1[0]")
	assert.Equal(t, "subnet-22222222", mountTarget["subnet_id"])
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

func TestPlanSourceTerraformECRPullThroughCacheWiring(t *testing.T) {
	t.Parallel()

	rootVariablesTF := readTerraformSource(t, "modules", "flex", "variables.tf")
	fleetVariablesTF := readTerraformSource(t, "modules", "fleet", "variables.tf")
	rootMainTF := readTerraformSource(t, "modules", "flex", "main.tf")
	extrasTF := readTerraformSource(t, "modules", "runner", "extras", "ecr_pull_through_cache.tf")
	extrasOutputsTF := readTerraformSource(t, "modules", "runner", "extras", "outputs.tf")
	computeIAMTF := readTerraformSource(t, "modules", "runner", "compute", "iam.tf")
	launchTemplatesTF := readTerraformSource(t, "modules", "runner", "compute", "launch_templates.tf")
	linuxUserData := readTerraformSource(t, "modules", "runner", "compute", "user-data", "linux-bootstrap.sh.tmpl")

	assert.Contains(t, rootVariablesTF, `variable "ecr_pull_through_cache_rules"`)
	assert.Contains(t, rootMainTF, "ecr_pull_through_cache_rules       = var.ecr_pull_through_cache_rules")

	assert.NotContains(t, extrasTF, `resource "aws_ecr_pull_through_cache_rule"`)
	assert.NotContains(t, extrasTF, `resource "aws_secretsmanager_secret"`)
	assert.NotContains(t, extrasTF, `ecr-pullthroughcache/${var.stack_name}/${each.key}`)
	assert.Contains(t, rootVariablesTF, `ecr_repository_prefix      = string`)
	assert.Contains(t, rootVariablesTF, `upstream_registry_url      = string`)
	assert.NotContains(t, rootVariablesTF, `provider                   = string`)
	assert.NotContains(t, rootVariablesTF, `credential_secret_arn`)
	assert.NotContains(t, rootVariablesTF, `credentials = optional`)
	assert.Contains(t, extrasTF, `registry-1.docker.io`)
	// Upstream-prefixed rules change the repository mapping, so they must not
	// configure Docker's transparent mirror.
	assert.Contains(t, extrasTF, `rule.upstream_repository_prefix == ""`)
	assert.Contains(t, extrasOutputsTF, `docker_hub_prefix`)
	assert.NotContains(t, extrasOutputsTF, `docker_hub_transparent`)

	// ROOT rules would grant runners account-wide ECR access; the module
	// rejects them and Docker Hub transparency comes from the runner-local
	// registry mirror instead.
	assert.Contains(t, rootVariablesTF, `upper(trimspace(rule.ecr_repository_prefix)) != "ROOT"`)
	assert.Contains(t, rootVariablesTF, `lower(trimspace(rule.upstream_registry_url)) == "registry-1.docker.io"`)
	assert.Contains(t, fleetVariablesTF, `lower(trimspace(rule.upstream_registry_url)) == "registry-1.docker.io"`)

	assert.Contains(t, computeIAMTF, `resource "aws_iam_role_policy" "ec2_ecr_pull_through_cache_access"`)
	assert.Contains(t, computeIAMTF, `ecr:BatchImportUpstreamImage`)
	assert.Contains(t, computeIAMTF, `ecr:CreateRepository`)
	assert.Contains(t, computeIAMTF, "repository/${rule.ecr_repository_prefix}/*")
	assert.NotContains(t, computeIAMTF, `repository/*`)
	assert.NotContains(t, computeIAMTF, "ecr_pull_through_isolation_tag")
	assert.NotContains(t, computeIAMTF, `resource "aws_iam_role_policy_attachment" "ec2_ecr_public"`)
	assert.Contains(t, computeIAMTF, `resource "aws_iam_role_policy" "ec2_ecr_public_read_only"`)
	assert.Contains(t, computeIAMTF, `name = "EcrPublicReadOnly"`)
	for _, action := range []string{
		"ecr-public:GetAuthorizationToken",
		"ecr-public:BatchCheckLayerAvailability",
		"ecr-public:GetRepositoryPolicy",
		"ecr-public:DescribeRepositories",
		"ecr-public:DescribeRegistries",
		"ecr-public:DescribeImages",
		"ecr-public:DescribeImageTags",
		"ecr-public:GetRepositoryCatalogData",
		"ecr-public:GetRegistryCatalogData",
		"sts:GetServiceBearerToken",
	} {
		assert.Contains(t, computeIAMTF, action)
	}
	assert.Contains(t, computeIAMTF, `"sts:AWSServiceName" = "ecr-public.amazonaws.com"`)
	assert.NotContains(t, computeIAMTF, `AmazonElasticContainerRegistryPublicFullAccess`)

	assert.Contains(t, launchTemplatesTF, `RUNS_ON_ECR_PULL_THROUGH_CACHE=`)
	assert.Contains(t, launchTemplatesTF, `RUNS_ON_ECR_PULL_THROUGH_CACHE_DOCKER_HUB_PREFIX=`)
	assert.Equal(t, 1, strings.Count(launchTemplatesTF, `RUNS_ON_ECR_PULL_THROUGH_CACHE_DOCKER_HUB_PREFIX`), "Docker Hub transparency is Linux-only")
	assert.NotContains(t, launchTemplatesTF, `RUNS_ON_ECR_PULL_THROUGH_CACHE_DOCKER_HUB_MIRROR`)
	assert.Contains(t, linuxUserData, `${EphemeralRegistryEnvLine}`)

	// The agent-side mirror: dockerd points at the always-on local server,
	// which rewrites Docker Hub paths onto the docker-hub cache prefix.
	agentRunnerUnix := readRepoSource(t, "pkg", "agent", "runner_unix.go")
	assert.Contains(t, agentRunnerUnix, "RUNS_ON_ECR_PULL_THROUGH_CACHE_DOCKER_HUB_PREFIX")
	assert.Contains(t, agentRunnerUnix, "setupDockerHubMirror")
	assert.NotContains(t, agentRunnerUnix, "dockerHubRegistryMirrorAuthAliases")
	agentMirror := readRepoSource(t, "pkg", "agent", "ecrmirror", "mirror.go")
	assert.Contains(t, agentMirror, `"/v2/" + m.prefix + "/" + rest`)
	agentLocalServer := readRepoSource(t, "pkg", "agent", "localserver", "server.go")
	assert.Contains(t, agentLocalServer, "const Port = 6871")
}

func TestPlanSourceCloudFormationRunnerRoleRestoresECRPublicRead(t *testing.T) {
	t.Parallel()

	template := readRepoSource(t, "cloudformation", "template.yaml")
	_, afterRole, ok := strings.Cut(template, "  EC2InstanceRole:")
	require.True(t, ok, "EC2InstanceRole resource should exist")
	roleBody, _, ok := strings.Cut(afterRole, "  EC2InstanceProfile:")
	require.True(t, ok, "EC2InstanceRole resource block should be delimited")

	assert.NotContains(t, roleBody, "AmazonElasticContainerRegistryPublic")
	assert.Contains(t, roleBody, "PolicyName: EcrPublicReadOnly")
	for _, action := range []string{
		"ecr-public:GetAuthorizationToken",
		"ecr-public:BatchCheckLayerAvailability",
		"ecr-public:GetRepositoryPolicy",
		"ecr-public:DescribeRepositories",
		"ecr-public:DescribeRegistries",
		"ecr-public:DescribeImages",
		"ecr-public:DescribeImageTags",
		"ecr-public:GetRepositoryCatalogData",
		"ecr-public:GetRegistryCatalogData",
		"sts:GetServiceBearerToken",
	} {
		assert.Contains(t, roleBody, action)
	}
	assert.Contains(t, roleBody, `"sts:AWSServiceName": ecr-public.amazonaws.com`)
}

func TestPlanSourceBootstrapServiceRejectsManualStops(t *testing.T) {
	t.Parallel()

	linuxUserData := readTerraformSource(t, "modules", "runner", "compute", "user-data", "linux-bootstrap.sh.tmpl")

	assert.Contains(t, linuxUserData, "RefuseManualStop=yes")
	assert.Contains(t, linuxUserData, "Restart=no")
	assert.NotContains(t, linuxUserData, "RefuseManualStart=yes")
}

func TestPlanSourceFleetECRPullThroughCacheReleaseWiring(t *testing.T) {
	t.Parallel()

	fleetMainTF := readTerraformSource(t, "modules", "fleet", "main.tf")
	fleetVariablesTF := readTerraformSource(t, "modules", "fleet", "variables.tf")
	stackMainTF := readRepoSource(t, "stacks", "tf", "modules", "fleet-stack", "main.tf")
	stackVariablesTF := readRepoSource(t, "stacks", "tf", "modules", "fleet-stack", "variables.tf")
	previewMainTF := readRepoSource(t, "stacks", "tf", "runs-on-fleet-preview-v3", "main.tf")
	stageMainTF := readRepoSource(t, "stacks", "tf", "runs-on-fleet-stage-v3", "main.tf")
	deployWorkflow := readRepoSource(t, ".github", "workflows", "core-deploy-terraform.yml")
	previewWorkflow := readRepoSource(t, ".github", "workflows", "core-preview.yml")
	stageWorkflow := readRepoSource(t, ".github", "workflows", "core-stage.yml")
	e2eWorkflow := readRepoSource(t, ".github", "workflows", "e2e-fleet-ecr-pull-through.yml")

	assert.Contains(t, fleetVariablesTF, `variable "ecr_pull_through_cache_rules"`)
	assert.Contains(t, fleetVariablesTF, `upper(trimspace(rule.ecr_repository_prefix)) != "ROOT"`)
	assert.Contains(t, fleetMainTF, "ecr_pull_through_cache_rules       = var.ecr_pull_through_cache_rules")
	assert.Contains(t, stackVariablesTF, `variable "ecr_pull_through_cache_rules"`)
	assert.Contains(t, stackVariablesTF, `variable "email"`)
	assert.Contains(t, stackMainTF, `extras = ["s3-cache", "ecr-pull-through", "otel"]`)
	assert.Contains(t, stackMainTF, "email                        = var.email")
	assert.Contains(t, stackMainTF, "ecr_pull_through_cache_rules = var.ecr_pull_through_cache_rules")
	assert.Contains(t, stackMainTF, "otel_exporter_endpoint       = var.otel_exporter_endpoint")
	assert.Contains(t, stackMainTF, "otel_exporter_headers        = var.otel_exporter_headers")
	assert.Contains(t, stackMainTF, "otel_exporter_temporality    = var.otel_exporter_temporality")
	assert.NotContains(t, previewMainTF, `data "aws_ecr_pull_through_cache_rule" "docker_hub"`)
	assert.Contains(t, previewMainTF, `ecr_repository_prefix      = "docker-hub"`)
	assert.NotContains(t, previewMainTF, `"ROOT"`)
	assert.Contains(t, previewMainTF, `upstream_registry_url      = "registry-1.docker.io"`)
	assert.Contains(t, previewMainTF, `email                        = "${var.workflow_environment}@runs-on.com"`)
	assert.Contains(t, previewMainTF, "ecr_pull_through_cache_rules = local.ecr_pull_through_cache_rules")
	assert.Contains(t, previewMainTF, "otel_exporter_endpoint       = var.otel_exporter_endpoint")
	assert.Contains(t, previewMainTF, "otel_exporter_headers        = var.otel_exporter_headers")
	assert.NotContains(t, stageMainTF, `data "aws_ecr_pull_through_cache_rule" "docker_hub"`)
	assert.Contains(t, stageMainTF, `ecr_repository_prefix      = "docker-hub"`)
	assert.NotContains(t, stageMainTF, `"ROOT"`)
	assert.Contains(t, stageMainTF, `upstream_registry_url      = "registry-1.docker.io"`)
	assert.Contains(t, stageMainTF, `email                        = "${var.workflow_environment}@runs-on.com"`)
	assert.Contains(t, stageMainTF, "ecr_pull_through_cache_rules = local.ecr_pull_through_cache_rules")
	assert.Contains(t, stageMainTF, "otel_exporter_endpoint       = var.otel_exporter_endpoint")
	assert.Contains(t, stageMainTF, "otel_exporter_headers        = var.otel_exporter_headers")

	assert.NotContains(t, deployWorkflow, "docker_hub_pull_through_cache_secret_arn")
	assert.NotContains(t, deployWorkflow, `ecr_pull_through_cache_rules = {`)
	assert.Contains(t, deployWorkflow, `-var "license_key=${RUNS_ON_LICENSE_KEY}"`)
	assert.NotContains(t, previewWorkflow, "FLEET_DOCKER_HUB_PULL_THROUGH_CACHE_SECRET_ARN")
	assert.NotContains(t, stageWorkflow, "FLEET_DOCKER_HUB_PULL_THROUGH_CACHE_SECRET_ARN")
	assert.Contains(t, previewWorkflow, `if: ${{ contains(github.event.pull_request.labels.*.name, 'e2e-private') && !contains(github.event.pull_request.labels.*.name, 'flex-only') && always() && needs.build.result == 'success' && needs.deploy-fleet-private-true.result == 'success' }}`)
	assert.Contains(t, stageWorkflow, `if: ${{ always() && needs.build.result == 'success' && needs.deploy-fleet-private-true.result == 'success' }}`)

	// The e2e run proves transparent Docker Hub pulls route through the
	// runner-local mirror (upstream hosts blackholed), explicit prefixed
	// references work, and reads outside the cache prefixes stay denied.
	assert.Contains(t, e2eWorkflow, "registry-1.docker.io")
	assert.Contains(t, e2eWorkflow, `index("http://127.0.0.1:6871")`)
	assert.Contains(t, e2eWorkflow, "docker pull docker.io/library/node:22")
	assert.Contains(t, e2eWorkflow, "docker run --rm docker.io/library/node:22 node --version")
	assert.Contains(t, e2eWorkflow, `docker pull "${RUNS_ON_ECR_PULL_THROUGH_CACHE}/docker-hub/library/node:20-alpine"`)
	assert.Contains(t, e2eWorkflow, "runs-on-e2e/isolation-canary")
	assert.Contains(t, e2eWorkflow, "AccessDeniedException")
	assert.NotContains(t, e2eWorkflow, "RUNS_ON_ECR_PULL_THROUGH_CACHE_DOCKER_HUB_MIRROR")
	assert.NotContains(t, e2eWorkflow, "id-token: write")
}

func TestPlanSourceFlexECRPullThroughCacheIntegrationWiring(t *testing.T) {
	t.Parallel()

	integrationWorkflow := readRepoSource(t, ".github", "workflows", "terraform-integration-runner.yml")
	terraformTestWorkflow := readRepoSource(t, ".github", "workflows", "terraform-test.yml")
	testHelpers := readTerraformSource(t, "modules", "flex", "test", "helpers.go")

	// The ephemeral Terraform integration stack references the shared
	// regional rule and requests the ecr-pull-through extra on a real Flex
	// runner. Blackholing Docker Hub makes a direct or fallback pull fail.
	assert.Contains(t, terraformTestWorkflow, `ENABLE_ECR_PULL_THROUGH_CACHE: "true"`)
	assert.Contains(t, terraformTestWorkflow, `RUNS_ON_TEST_WORKFLOW_INPUTS: '{"test_ecr_mirror":true}'`)
	assert.Contains(t, testHelpers, `"ecr_pull_through_cache_rules"`)
	assert.Contains(t, testHelpers, `"ecr_repository_prefix":      "docker-hub"`)
	assert.Contains(t, integrationWorkflow, "extras=ecr-pull-through")
	assert.Contains(t, integrationWorkflow, "registry-1.docker.io")
	assert.Contains(t, integrationWorkflow, `index("http://127.0.0.1:6871")`)
	assert.Contains(t, integrationWorkflow, "docker pull docker.io/library/node:22")
	assert.Contains(t, integrationWorkflow, "runs-on-e2e/isolation-canary")
	assert.Contains(t, integrationWorkflow, "AccessDeniedException")
	assert.Contains(t, integrationWorkflow, `"runs-on-environment"`)
	assert.Contains(t, integrationWorkflow, `"Environment"`)
}

func TestPlanSourceFlexCloudFormationUsesRepositoryLicenseSecret(t *testing.T) {
	t.Parallel()

	deployWorkflow := readRepoSource(t, ".github", "workflows", "core-deploy.yml")
	previewWorkflow := readRepoSource(t, ".github", "workflows", "core-preview.yml")
	stageWorkflow := readRepoSource(t, ".github", "workflows", "core-stage.yml")

	assert.Contains(t, deployWorkflow, `runs_on_license_key:`)
	assert.Contains(t, deployWorkflow, `RUNS_ON_LICENSE_KEY: ${{ secrets.runs_on_license_key }}`)
	assert.Contains(t, deployWorkflow, `$overrides + {LicenseKey: $license_key}`)
	assert.Contains(t, deployWorkflow, `bash ./scripts/write-cloudformation-parameters.sh "${PARAMETERS_FILE}"`)

	assert.Equal(t, 3, strings.Count(previewWorkflow, "cloudformation_parameters_json: ${{ secrets.CLOUDFORMATION_PARAMETERS_PREVIEW_JSON }}\n      runs_on_license_key: ${{ secrets.RUNS_ON_LICENSE_KEY }}"))
	assert.Equal(t, 3, strings.Count(stageWorkflow, "cloudformation_parameters_json: ${{ secrets.CLOUDFORMATION_PARAMETERS_STAGE_JSON }}\n      runs_on_license_key: ${{ secrets.RUNS_ON_LICENSE_KEY }}"))
}
