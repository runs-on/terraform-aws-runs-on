package test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

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

func TestPlanSourceStackConfigMaterializerWiring(t *testing.T) {
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

func TestPlanSourceManagedWAFIPSetsAreLambdaOwned(t *testing.T) {
	t.Parallel()

	wafTF := readTerraformSource(t, "modules", "control_plane", "flex", "waf.tf")

	assert.NotContains(t, wafTF, "192.0.2.1/32")
	assert.NotContains(t, wafTF, "2001:db8::1/128")

	for _, resourceName := range []string{"allowed_ips_ipv4", "allowed_ips_ipv6"} {
		_, afterResource, ok := strings.Cut(wafTF, `resource "aws_wafv2_ip_set" "`+resourceName+`"`)
		require.Truef(t, ok, "expected %s IP set resource to exist", resourceName)

		resourceBody, _, ok := strings.Cut(afterResource, `resource "aws_`)
		require.Truef(t, ok, "expected %s IP set resource body to be delimited", resourceName)

		assert.Contains(t, resourceBody, "addresses = []")
		assert.Contains(t, resourceBody, "ignore_changes = [addresses]")
	}
}

func TestPlanSourceGitHubRunnerCacheRefreshSeedWiring(t *testing.T) {
	t.Parallel()

	githubRunnerCacheTF := readTerraformSource(t, "modules", "control_plane", "flex", "github_runner_cache.tf")

	assert.Contains(t, githubRunnerCacheTF, `resource "aws_lambda_invocation" "github_runner_cache_refresh_seed"`)
	assert.Contains(t, githubRunnerCacheTF, "function_name = aws_lambda_function.github_runner_cache_refresh.function_name")
	assert.Contains(t, githubRunnerCacheTF, "bucket = var.extras.cache.bucket_name")
	assert.NotContains(t, githubRunnerCacheTF, "lifecycle_scope")
	assert.NotContains(t, githubRunnerCacheTF, "triggers =")
}

func TestPlanSourceCustomPolicyWiring(t *testing.T) {
	t.Parallel()

	mainTF := readTerraformSource(t, "modules", "flex", "main.tf")
	serviceTF := readTerraformSource(t, "modules", "control_plane", "flex", "service.tf")

	assert.Contains(t, mainTF, "custom_policy_arn         = var.app_custom_policy_arn")
	assert.Contains(t, mainTF, "runner_custom_policy_arn = var.runner_custom_policy_arn")
	assert.Contains(t, serviceTF, "task_role_managed_policy_arns   = compact([local.runtime.custom_policy_arn])")
}

func TestPlanSourceCloudFormationEphemeralRegistryUsesGeneratedNameAndStackTags(t *testing.T) {
	t.Parallel()

	template := readRepoSource(t, "cloudformation", "template.yaml")
	_, afterResource, ok := strings.Cut(template, "  EphemeralRegistry:")
	require.True(t, ok, "EphemeralRegistry resource should exist")
	resourceBody, _, ok := strings.Cut(afterResource, "  # --- End Ephemeral Registry Resources ---")
	require.True(t, ok, "ephemeral registry resource block should be delimited")

	assert.NotContains(t, resourceBody, "RepositoryName")
	assert.Contains(t, resourceBody, "Tags:")
	assert.Contains(t, resourceBody, "Key: !Ref CostAllocationTag")
	assert.Contains(t, resourceBody, "Key: runs-on-stack-name")
	assert.Contains(t, resourceBody, "Value: !Ref AWS::StackName")
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
