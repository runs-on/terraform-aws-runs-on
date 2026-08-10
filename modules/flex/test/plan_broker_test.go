package test

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

// TestPlanSourceCacheCredentialBrokerWiring pins the reduced broker design:
// broker-minted sessions carry only the per-token scoped-cache statements (no
// base session policy, no packed-policy pressure), the scoped namespace lives
// outside cache/ so legacy instance-role grants never reach it, and legacy
// cache statements stay untouched.
func TestPlanSourceCacheCredentialBrokerWiring(t *testing.T) {
	t.Parallel()

	brokerTF := readTerraformSource(t, "modules", "control_plane", "flex", "cache_credential_broker.tf")
	fleetBrokerTF := readTerraformSource(t, "modules", "control_plane", "fleet", "cache_credential_broker.tf")
	computeIAM := readTerraformSource(t, "modules", "runner", "compute", "iam.tf")
	extrasS3 := readTerraformSource(t, "modules", "runner", "extras", "s3.tf")
	brokerJS := readRepoSource(t, "terraform", "lambdas", "cache_credential_broker.js")
	cloudFormation := readRepoSource(t, "cloudformation", "template.yaml")

	for name, tf := range map[string]string{"flex": brokerTF, "fleet": fleetBrokerTF} {
		assert.Contains(t, tf, `resource "aws_lambda_function" "cache_credential_broker"`, name)
		// The scoped statements ARE the whole session policy — no static base
		// boundary to keep in sync or to blow the STS packed-policy budget.
		assert.NotContains(t, tf, `BASE_SESSION_POLICY`, name)
		assert.NotContains(t, tf, `NotAction`, name)
		assert.Contains(t, tf, `GITHUB_ENTERPRISE_URL`, name)
		assert.Contains(t, tf, `GITHUB_TOKEN_ISSUER`, name)
		assert.Contains(t, tf, `RUNNER_ROLE_ARN`, name)
		// The prefix derives from the token's signed repository IDs: the broker
		// reads no runner-identity object. Its only S3 permission is the single
		// control-plane-published JWKS key it validates tokens against.
		assert.NotContains(t, tf, `runner-identity.json`, name)
		assert.Contains(t, tf, `/agents/github-jwks.json`, name)
		assert.NotContains(t, tf, `s3:ListBucket`, name)
		assert.Contains(t, tf, `sts:TagSession`, name)
		assert.Contains(t, tf, `aws:RequestTag/runs-on-cache-brokered`, name)
	}

	// Runner role: legacy cache statements stay byte-identical to the
	// pre-broker layout; the scoped namespace is additive and tag-gated.
	assert.Contains(t, computeIAM, `"cache/*",`)
	assert.Contains(t, computeIAM, `scoped-cache/*`)
	assert.Contains(t, computeIAM, `aws:PrincipalTag/runs-on-cache-brokered`)
	assert.Contains(t, computeIAM, `"aws:userid" = "*:runs-on-cache-i-*"`)
	assert.Contains(t, computeIAM, `arn:${local.partition}:iam::${var.account_id}:root`)
	assert.Contains(t, computeIAM, `aws:PrincipalArn`)
	assert.Contains(t, computeIAM, `sts:TagSession`)
	assert.Contains(t, computeIAM, `arn:${local.partition}:lambda:${var.region}:${var.account_id}:function:${var.stack_name}-cache-broker`)

	// The scoped namespace is a sibling of cache/, with its own expiry rule.
	assert.Contains(t, extrasS3, `prefix = "scoped-cache/"`)

	// The Lambda mints from the runtime token only and roots prefixes at the
	// sibling namespace, keyed on the token's signed repository IDs.
	assert.Contains(t, brokerJS, `scoped-cache/`)
	assert.Contains(t, brokerJS, `repository_owner_id`)
	assert.Contains(t, brokerJS, `repository_id`)
	assert.NotContains(t, brokerJS, `BASE_SESSION_POLICY`)
	assert.NotContains(t, brokerJS, `runner-identity.json`)
	assert.Contains(t, brokerJS, `runtime token is required`)
	assert.Contains(t, brokerJS, `runs-on-cache-`)

	// CloudFormation mirrors the Terraform design.
	assert.Contains(t, cloudFormation, `function:${AWS::StackName}-cache-broker`)
	assert.Contains(t, cloudFormation, `scoped-cache/*`)
	assert.Contains(t, cloudFormation, `aws:userid: "*:runs-on-cache-i-*"`)
	assert.NotContains(t, cloudFormation, `BASE_SESSION_POLICY`)
	assert.Contains(t, cloudFormation, `Id: ExpireScopedCache`)
	assert.Contains(t, cloudFormation, `aws:RequestTag/runs-on-cache-brokered`)
	assert.NotContains(t, cloudFormation, `RunsOnCacheCredentialBrokerReadRunnerIdentityPolicy`)
	assert.Contains(t, cloudFormation, `RunsOnCacheCredentialBrokerReadJwksPolicy`)
	assert.Contains(t, cloudFormation, `/agents/github-jwks.json`)
	assert.NotContains(t, cloudFormation, `AWSLambdaBasicExecutionRole`)
	assert.Contains(t, cloudFormation, `RunsOnCacheCredentialBrokerLogsPolicy`)
	assert.Contains(t, cloudFormation, `Resource: !Sub "${RunsOnCacheCredentialBrokerLogGroup.Arn}:*"`)
}
