package test

import (
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/random"
)

// GetTestID generates a unique test ID for resource naming
func GetTestID() string {
	return fmt.Sprintf("%d", time.Now().Unix())
}

// GetRandomStackName generates a random stack name for testing
func GetRandomStackName(prefix string) string {
	return fmt.Sprintf("%s-%s", prefix, random.UniqueId())
}

// GetRequiredEnv gets a required environment variable or fails the test
func GetRequiredEnv(t *testing.T, key string, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		if fallback != "" {
			t.Logf("WARNING: %s not set, using fallback value", key)
			return fallback
		}
		t.Fatalf("Required environment variable %s is not set", key)
	}
	return value
}

// GetOptionalEnv gets an optional environment variable with a default
func GetOptionalEnv(key string, defaultValue string) string {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value
}

// GetAWSRegion returns the AWS region for tests
func GetAWSRegion() string {
	return GetOptionalEnv("AWS_REGION", "us-east-1")
}

// GetTestTags returns common tags for test resources
func GetTestTags(testName string) map[string]string {
	return map[string]string{
		"TestFramework": "terratest",
		"TestName":      testName,
		"TestID":        GetTestID(),
		"ManagedBy":     "terragrunt",
		"AutoCleanup":   "true",
	}
}
