package test

import (
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// planVars returns the minimum required variables for `tofu plan` with dummy values.
// Overrides are applied on top of the base set.
func planVars(overrides map[string]interface{}) map[string]interface{} {
	vars := map[string]interface{}{
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
		"private_mode":                       "false",
		"security_group_ids":                 []string{},
		"force_destroy_buckets":              true,
		"force_delete_ecr":                   true,
		"prevent_destroy_optional_resources": false,
	}
	for k, v := range overrides {
		vars[k] = v
	}
	return vars
}

// planOptions returns terraform.Options configured for plan-only testing.
func planOptions(overrides map[string]interface{}) *terraform.Options {
	return &terraform.Options{
		TerraformDir:    "../",
		TerraformBinary: "tofu",
		Vars:            planVars(overrides),
		NoColor:         true,
	}
}

// TestPlanConditionalResources validates that feature flags control which resources are planned.
// These tests run `tofu plan` with dummy values — no AWS resources are created.
func TestPlanConditionalResources(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name          string
		overrides     map[string]interface{}
		expectPresent []string // resource type patterns expected in plan output
		expectAbsent  []string // resource type patterns NOT expected in plan output
	}{
		{
			name:      "BaselineNoOptional",
			overrides: map[string]interface{}{},
			expectAbsent: []string{
				"aws_efs_file_system",
				"aws_ecr_repository",
				"aws_apprunner_vpc_connector",
			},
		},
		{
			name: "EFSOnly",
			overrides: map[string]interface{}{
				"enable_efs": true,
			},
			expectPresent: []string{
				"aws_efs_file_system",
				"aws_efs_mount_target",
				"aws_security_group.efs",
			},
			expectAbsent: []string{
				"aws_ecr_repository",
			},
		},
		{
			name: "ECROnly",
			overrides: map[string]interface{}{
				"enable_ecr": true,
			},
			expectPresent: []string{
				"aws_ecr_repository",
				"aws_ecr_lifecycle_policy",
			},
			expectAbsent: []string{
				"aws_efs_file_system",
			},
		},
		{
			name: "PrivateModeTrue",
			overrides: map[string]interface{}{
				"private_mode":       "true",
				"private_subnet_ids": []string{"subnet-22222222"},
			},
			expectPresent: []string{
				"aws_apprunner_vpc_connector",
				"time_sleep",
			},
		},
		{
			name: "PrivateModeAlways",
			overrides: map[string]interface{}{
				"private_mode":       "always",
				"private_subnet_ids": []string{"subnet-22222222"},
			},
			expectPresent: []string{
				"aws_apprunner_vpc_connector",
			},
		},
		{
			name: "AllFeatures",
			overrides: map[string]interface{}{
				"enable_efs":         true,
				"enable_ecr":         true,
				"private_mode":       "true",
				"private_subnet_ids": []string{"subnet-22222222"},
			},
			expectPresent: []string{
				"aws_efs_file_system",
				"aws_ecr_repository",
				"aws_apprunner_vpc_connector",
			},
		},
		{
			name: "SGCreatedWhenEmpty",
			overrides: map[string]interface{}{
				"security_group_ids": []string{},
			},
			expectPresent: []string{
				"aws_security_group.runners",
			},
		},
		{
			name: "SGNotCreatedWhenProvided",
			overrides: map[string]interface{}{
				"security_group_ids": []string{"sg-12345678"},
			},
			expectAbsent: []string{
				"aws_security_group.runners",
			},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			opts := planOptions(tc.overrides)
			planOutput := terraform.InitAndPlan(t, opts)

			for _, pattern := range tc.expectPresent {
				assert.True(t, strings.Contains(planOutput, pattern),
					"Expected resource matching %q in plan output", pattern)
			}
			for _, pattern := range tc.expectAbsent {
				assert.False(t, strings.Contains(planOutput, pattern),
					"Did not expect resource matching %q in plan output", pattern)
			}
		})
	}
}

// TestPlanResourceCounts verifies the baseline deployment creates a reasonable number of resources.
func TestPlanResourceCounts(t *testing.T) {
	t.Parallel()

	opts := planOptions(nil)
	planOutput := terraform.InitAndPlan(t, opts)

	// Count resources that "will be created"
	createdCount := strings.Count(planOutput, "will be created")
	assert.GreaterOrEqual(t, createdCount, 30,
		"Baseline plan should create at least 30 resources, got %d", createdCount)

	t.Logf("Baseline plan creates %d resources", createdCount)
}
