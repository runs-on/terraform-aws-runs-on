package test

import (
	"archive/zip"
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

func TestPlanSourceTerraformLambdaArtifactsAreBundled(t *testing.T) {
	t.Parallel()

	for _, parts := range [][]string{
		{"modules", "control_plane", "alerts", "main.tf"},
		{"modules", "control_plane", "fleet", "job_diagnostics_resolver.tf"},
		{"modules", "control_plane", "fleet", "main.tf"},
		{"modules", "control_plane", "fleet", "secrets.tf"},
		{"modules", "control_plane", "flex", "github_runner_cache.tf"},
		{"modules", "control_plane", "flex", "ingress.tf"},
		{"modules", "control_plane", "flex", "job_diagnostics_resolver.tf"},
		{"modules", "control_plane", "flex", "main.tf"},
		{"modules", "control_plane", "flex", "secrets.tf"},
		{"modules", "control_plane", "flex", "waf.tf"},
	} {
		source := readTerraformSource(t, parts...)
		assert.NotContains(t, source, `data "archive_file"`, strings.Join(parts, "/"))
		assert.NotContains(t, source, `data.archive_file`, strings.Join(parts, "/"))
		assert.NotContains(t, source, `hashicorp/archive`, strings.Join(parts, "/"))
		assert.NotContains(t, source, `path.root}/.terraform`, strings.Join(parts, "/"))
	}

	for _, artifact := range []struct {
		name      string
		zipEntry  string
		reference string
	}{
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
	assert.Contains(t, serviceTF, "aws_lambda_invocation.stack_config_materializer")
}

func TestPlanSourceFleetConfigMaterializerWiring(t *testing.T) {
	t.Parallel()

	mainTF := readTerraformSource(t, "modules", "control_plane", "fleet", "main.tf")
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
	assert.Contains(t, mainTF, "aws_lambda_invocation.config_materializer")
	assert.Contains(t, mainTF, `deployment_method                      = "terraform"`)
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

	_, afterRunner, ok := strings.Cut(mainTF, "small-x64 = {")
	require.True(t, ok, "small-x64 runner should be configured")

	smallRunner, _, ok := strings.Cut(afterRunner, "fast-x64 = {")
	require.True(t, ok, "small-x64 runner block should end before fast-x64")

	assert.Contains(t, smallRunner, `extras = ["s3-cache", "ecr-pull-through"]`)
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
	assert.Contains(t, githubRunnerCacheTF, "triggers =")
	assert.Contains(t, githubRunnerCacheTF, "lambda_version = aws_lambda_function.github_runner_cache_refresh.source_code_hash")
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

func TestPlanSourceCloudFormationStackConfigUsesDeploymentMethod(t *testing.T) {
	t.Parallel()

	template := readRepoSource(t, "cloudformation", "template.yaml")

	assert.Contains(t, template, `DeploymentMethod: "cloudformation"`)
	assert.NotContains(t, template, "InfrastructureSource")
}

func TestPlanSourceCloudFormationCostAllocationTagScheduleFollowsCostReports(t *testing.T) {
	t.Parallel()

	template := readRepoSource(t, "cloudformation", "template.yaml")
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

func TestPlanSourceTerraformECRPullThroughCacheWiring(t *testing.T) {
	t.Parallel()

	rootVariablesTF := readTerraformSource(t, "modules", "flex", "variables.tf")
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
	assert.Contains(t, extrasTF, `rule.ecr_repository_prefix == "ROOT"`)
	assert.Contains(t, extrasOutputsTF, `docker_hub_transparent`)

	assert.Contains(t, computeIAMTF, `resource "aws_iam_role_policy" "ec2_ecr_pull_through_cache_access"`)
	assert.Contains(t, computeIAMTF, `ecr:BatchImportUpstreamImage`)
	assert.Contains(t, computeIAMTF, `ecr:CreateRepository`)
	assert.Contains(t, computeIAMTF, `AmazonElasticContainerRegistryPublicReadOnly`)
	assert.NotContains(t, computeIAMTF, `AmazonElasticContainerRegistryPublicFullAccess`)

	assert.Contains(t, launchTemplatesTF, `RUNS_ON_ECR_PULL_THROUGH_CACHE=`)
	assert.Contains(t, launchTemplatesTF, `RUNS_ON_ECR_PULL_THROUGH_CACHE_DOCKER_HUB_MIRROR=`)
	assert.Contains(t, linuxUserData, `${EphemeralRegistryEnvLine}`)
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
	assert.Contains(t, fleetMainTF, "ecr_pull_through_cache_rules       = var.ecr_pull_through_cache_rules")
	assert.Contains(t, stackVariablesTF, `variable "ecr_pull_through_cache_rules"`)
	assert.Contains(t, stackVariablesTF, `variable "email"`)
	assert.Contains(t, stackMainTF, `extras = ["s3-cache", "ecr-pull-through"]`)
	assert.Contains(t, stackMainTF, "email                        = var.email")
	assert.Contains(t, stackMainTF, "ecr_pull_through_cache_rules = var.ecr_pull_through_cache_rules")
	assert.NotContains(t, previewMainTF, `data "aws_ecr_pull_through_cache_rule" "docker_hub"`)
	assert.Contains(t, previewMainTF, `ecr_repository_prefix      = "ROOT"`)
	assert.Contains(t, previewMainTF, `upstream_registry_url      = "registry-1.docker.io"`)
	assert.Contains(t, previewMainTF, `email                        = "${var.workflow_environment}@runs-on.com"`)
	assert.Contains(t, previewMainTF, "ecr_pull_through_cache_rules = local.ecr_pull_through_cache_rules")
	assert.NotContains(t, stageMainTF, `data "aws_ecr_pull_through_cache_rule" "docker_hub"`)
	assert.Contains(t, stageMainTF, `ecr_repository_prefix      = "ROOT"`)
	assert.Contains(t, stageMainTF, `upstream_registry_url      = "registry-1.docker.io"`)
	assert.Contains(t, stageMainTF, `email                        = "${var.workflow_environment}@runs-on.com"`)
	assert.Contains(t, stageMainTF, "ecr_pull_through_cache_rules = local.ecr_pull_through_cache_rules")

	assert.NotContains(t, deployWorkflow, "docker_hub_pull_through_cache_secret_arn")
	assert.NotContains(t, deployWorkflow, `ecr_pull_through_cache_rules = {`)
	assert.Contains(t, deployWorkflow, `-var "license_key=${RUNS_ON_LICENSE_KEY}"`)
	assert.NotContains(t, previewWorkflow, "FLEET_DOCKER_HUB_PULL_THROUGH_CACHE_SECRET_ARN")
	assert.NotContains(t, stageWorkflow, "FLEET_DOCKER_HUB_PULL_THROUGH_CACHE_SECRET_ARN")
	assert.Contains(t, previewWorkflow, `if: ${{ always() && needs.build.result == 'success' && needs.deploy-fleet-private-true.result == 'success' }}`)
	assert.Contains(t, stageWorkflow, `if: ${{ always() && needs.build.result == 'success' && needs.deploy-fleet-private-true.result == 'success' }}`)

	assert.Contains(t, e2eWorkflow, "RUNS_ON_ECR_PULL_THROUGH_CACHE_DOCKER_HUB_MIRROR")
	assert.Contains(t, e2eWorkflow, "registry-1.docker.io")
	assert.Contains(t, e2eWorkflow, "docker pull docker.io/library/node:22")
	assert.Contains(t, e2eWorkflow, "docker run --rm docker.io/library/node:22 node --version")
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
