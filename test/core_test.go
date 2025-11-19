package test

import (
	"testing"
)

// TestCoreModuleSQSQueues tests SQS queue creation
// NOTE: Core module requires dependencies from storage and compute modules
// Use integration tests or Terragrunt scenarios for complete testing
func TestCoreModuleSQSQueues(t *testing.T) {
	t.Skip("Skipping - core module requires storage and compute module outputs. Use integration tests instead.")
}

// TestCoreModuleDynamoDBTables tests DynamoDB table creation
func TestCoreModuleDynamoDBTables(t *testing.T) {
	t.Skip("Skipping - core module requires dependencies. Use integration tests instead.")
}

// TestCoreModuleAppRunnerService tests App Runner service creation
func TestCoreModuleAppRunnerService(t *testing.T) {
	t.Skip("Skipping - core module requires dependencies. Use integration tests instead.")
}

// TestCoreModuleVPCConnector tests VPC connector creation with private networking
func TestCoreModuleVPCConnector(t *testing.T) {
	t.Skip("Skipping - use private-networking scenario test instead")
}

// TestCoreModuleSNSTopic tests SNS topic and subscriptions
func TestCoreModuleSNSTopic(t *testing.T) {
	t.Skip("Skipping - core module requires dependencies. Use integration tests instead.")
}

// NOTE: Core module tests are better suited for integration/scenario tests
// because the module has extensive dependencies on storage, compute, and optional modules.
// See scenarios_test.go for complete testing of core module functionality.
