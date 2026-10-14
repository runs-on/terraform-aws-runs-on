package test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
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

func TestPlanUpgradeMovesV30Addresses(t *testing.T) {
	t.Parallel()

	// v3.0.x state for objects whose address changed later. A missing move
	// plans a delete and a create of the same AWS object, and their order is
	// not defined: if the delete runs last, the object is gone after apply.
	type object struct {
		module, kind, name string
		counted            bool // declared with count in v3.0.x
		attributes         map[string]any
		to                 string // empty when the address did not change
	}
	const (
		customPolicyARN = "arn:aws:iam::123456789012:policy/test-plan-custom"
		topicARN        = "arn:aws:sns:us-east-1:123456789012:test-plan-alerts"
		ecrName         = "runs-on-a1b2c3d4-ephemeral-registry"
	)
	// v3.0.0-v3.0.2 named the repository after prevent_destroy_optional_resources.
	ecr := func(name string) []object {
		return []object{
			{
				module: "module.extras", kind: "random_id", name: "ephemeral_registry", counted: true,
				attributes: map[string]any{"id": "obLD1A", "b64_url": "obLD1A", "b64_std": "obLD1A==", "byte_length": 4, "dec": "2712847316", "hex": "a1b2c3d4"},
			},
			{
				module: "module.extras", kind: "aws_ecr_repository", name: name, counted: true,
				attributes: map[string]any{
					"id": ecrName, "name": ecrName, "arn": "arn:aws:ecr:us-east-1:123456789012:repository/" + ecrName,
					"registry_id": "123456789012", "repository_url": "123456789012.dkr.ecr.us-east-1.amazonaws.com/" + ecrName,
					"image_tag_mutability": "MUTABLE", "force_delete": false,
					"encryption_configuration":     []any{map[string]any{"encryption_type": "AES256", "kms_key": ""}},
					"image_scanning_configuration": []any{map[string]any{"scan_on_push": false}},
				},
				to: "module.extras.aws_ecr_repository.ephemeral[0]",
			},
		}
	}
	states := map[string][]object{
		"custom policy, alert topic, protected ECR": append([]object{
			{
				module: "module.compute", kind: "aws_iam_role_policy_attachment", name: "ec2_custom", counted: true,
				attributes: map[string]any{
					"id": "test-plan-ec2-instance-role/" + customPolicyARN, "role": "test-plan-ec2-instance-role", "policy_arn": customPolicyARN,
				},
				to: "module.compute.aws_iam_role_policy_attachment.ec2_custom_additional[0]",
			},
			{
				module: "module.control_plane", kind: "aws_sns_topic", name: "alerts",
				attributes: map[string]any{"id": topicARN, "arn": topicARN, "name": "test-plan-alerts", "display_name": "RunsOn Alerts", "fifo_topic": false},
				to:         "module.control_plane.module.alerts.aws_sns_topic.alerts",
			},
			{
				module: "module.control_plane", kind: "aws_sns_topic_policy", name: "alerts",
				attributes: map[string]any{"id": topicARN, "arn": topicARN, "policy": "{}"},
				to:         "module.control_plane.module.alerts.aws_sns_topic_policy.alerts[0]",
			},
		}, ecr("ephemeral_protected")...),
		"unprotected ECR": ecr("ephemeral_unprotected"),
	}
	for name, objects := range states {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			resources := make([]any, 0, len(objects))
			for _, object := range objects {
				instance := map[string]any{"schema_version": 0, "attributes": object.attributes}
				if object.counted {
					instance["index_key"] = 0
				}
				resources = append(resources, map[string]any{
					"module":    object.module,
					"mode":      "managed",
					"type":      object.kind,
					"name":      object.name,
					"provider":  `provider["registry.opentofu.org/hashicorp/` + strings.SplitN(object.kind, "_", 2)[0] + `"]`,
					"instances": []any{instance},
				})
			}
			stateJSON, err := json.Marshal(map[string]any{
				"version": 4, "serial": 1, "lineage": "test-upgrade-v30-addresses", "resources": resources,
			})
			require.NoError(t, err)
			statePath := filepath.Join(t.TempDir(), "terraform.tfstate")
			require.NoError(t, os.WriteFile(statePath, stateJSON, 0o600))

			options := newPlanOptions(t, map[string]any{"runner_custom_policy_arns": []string{customPolicyARN}, "enable_ecr": true})
			mustRunTerraformCommandQuietly(t, options, "plan", "-input=false", "-lock=false", "-refresh=false", "-state="+statePath)
			plan, err := terraform.ParsePlanJSON(mustRunTerraformCommandQuietly(t, options, "show", "-json"))
			require.NoError(t, err)
			for _, object := range objects {
				from := object.module + "." + object.kind + "." + object.name
				if object.counted {
					from += "[0]"
				}
				to := from
				if object.to != "" {
					to = object.to
				}
				change := plan.ResourceChangesMap[to]
				require.NotNil(t, change, to)
				if object.to != "" {
					assert.Equal(t, from, change.PreviousAddress, "%s must move, not be recreated", from)
				}
				assert.True(t, change.Change.Actions.NoOp() || change.Change.Actions.Update(), "%s must stay in place, got %v (replace paths %v)", to, change.Change.Actions, change.Change.ReplacePaths)
			}
		})
	}
}
