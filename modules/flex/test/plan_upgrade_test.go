package test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestPlanUpgradeDiagnosticsLogGroup(t *testing.T) {
	t.Parallel()

	// Keep only the v3.1.0 state needed for this upgrade graph. The old
	// deployment depended on the resolver through the setup Lambda's stack
	// config hash. The current config computes the resolver name directly,
	// removing that dependency while also replacing the resolver's log group.
	const prefix = "module.control_plane."
	resource := func(kind, name string, attributes map[string]any, dependencies ...string) map[string]any {
		return map[string]any{
			"module":   "module.control_plane",
			"mode":     "managed",
			"type":     kind,
			"name":     name,
			"provider": `provider["registry.opentofu.org/hashicorp/aws"]`,
			"instances": []any{map[string]any{
				"schema_version":        0,
				"attributes":            attributes,
				"dependencies":          dependencies,
				"create_before_destroy": kind != "aws_api_gateway_stage",
			}},
		}
	}
	state := map[string]any{
		"version": 4,
		"serial":  1,
		"lineage": "test-upgrade-diagnostics",
		"resources": []any{
			resource("aws_api_gateway_rest_api", "public_ingress", map[string]any{
				"id": "testapi123", "name": "test-plan-public-ingress", "root_resource_id": "testroot",
				"endpoint_configuration": []any{map[string]any{"types": []string{"REGIONAL"}}},
			}),
			resource("aws_cloudwatch_log_group", "job_diagnostics_resolver", map[string]any{
				"id":                "/aws/lambda/test-plan-job-diagnostics-resolver",
				"name":              "/aws/lambda/test-plan-job-diagnostics-resolver",
				"arn":               "arn:aws:logs:us-east-1:123456789012:log-group:/aws/lambda/test-plan-job-diagnostics-resolver",
				"retention_in_days": 14,
			}),
			resource("aws_lambda_function", "job_diagnostics_resolver", map[string]any{
				"id": "test-plan-job-diagnostics-resolver", "function_name": "test-plan-job-diagnostics-resolver",
				"role":    "arn:aws:iam::123456789012:role/test-plan-job-diagnostics-resolver-role",
				"runtime": "nodejs24.x", "handler": "index.handler", "package_type": "Zip",
				"timeout": 30, "memory_size": 256,
			}, prefix+"aws_cloudwatch_log_group.job_diagnostics_resolver"),
			resource("aws_api_gateway_deployment", "public_ingress", map[string]any{
				"id": "olddeploy", "rest_api_id": "testapi123",
				"triggers": map[string]string{"redeployment": "old-code-hash"},
			}, prefix+"aws_api_gateway_rest_api.public_ingress", prefix+"aws_lambda_function.job_diagnostics_resolver", prefix+"aws_cloudwatch_log_group.job_diagnostics_resolver"),
			resource("aws_api_gateway_stage", "public_ingress", map[string]any{
				"id": "ags-testapi123-prod", "rest_api_id": "testapi123", "deployment_id": "olddeploy", "stage_name": "prod",
			}, prefix+"aws_api_gateway_deployment.public_ingress", prefix+"aws_lambda_function.job_diagnostics_resolver", prefix+"aws_cloudwatch_log_group.job_diagnostics_resolver"),
		},
	}
	stateJSON, err := json.Marshal(state)
	require.NoError(t, err)
	statePath := filepath.Join(t.TempDir(), "terraform.tfstate")
	require.NoError(t, os.WriteFile(statePath, stateJSON, 0o600))

	options := newPlanOptions(t, nil)
	mustRunTerraformCommandQuietly(t, options, "plan", "-input=false", "-lock=false", "-refresh=false", "-state="+statePath)
	plan, err := terraform.ParsePlanJSON(mustRunTerraformCommandQuietly(t, options, "show", "-json"))
	require.NoError(t, err)
	change := plan.ResourceChangesMap[prefix+"aws_cloudwatch_log_group.job_diagnostics_resolver"]
	require.NotNil(t, change)
	assert.True(t, change.Change.Actions.CreateBeforeDestroy(), "create the new log group before deleting the old one")
	for _, address := range []string{"aws_lambda_function.job_diagnostics_resolver", "aws_api_gateway_stage.public_ingress"} {
		change := plan.ResourceChangesMap[prefix+address]
		require.NotNil(t, change)
		assert.True(t, change.Change.Actions.Update(), "%s must stay in place", address)
	}
}
