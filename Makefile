VERSION ?= $(shell if [ -f ../VERSION ]; then tr -d '\n' < ../VERSION; elif [ -f VERSION ]; then tr -d '\n' < VERSION; elif git describe --tags --exact-match >/dev/null 2>&1; then git describe --tags --exact-match; else echo dev; fi)

# Dev deploy config
DEV_VPC_DIR = test/fixtures/vpc
DEV_TFVARS = dev.tfvars
DEV_STACK_NAME ?= runs-on-tf
TEST_GO = cd test && mise exec -- go
TEST_WITH_CI_IMAGE = $(TEST_GO) run ./cmd/with-ci-image

.PHONY: help init validate fmt fmt-check lint security quick docs clean sync-metadata \
	test test-plan test-basic test-private test-full test-integration test-short test-all \
	test-basic-ci-image test-private-ci-image test-full-ci-image test-integration-ci-image \
	dev-vpc dev-apply dev-destroy dev-output \
	check

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

init: ## Initialize OpenTofu
	@echo "Initializing OpenTofu..."
	@tofu init -upgrade

validate: ## Validate OpenTofu syntax
	@echo "Validating OpenTofu..."
	@tofu validate

fmt: ## Format OpenTofu files
	@echo "Formatting OpenTofu files..."
	@tofu fmt -recursive

fmt-check: ## Check if OpenTofu files are formatted
	@echo "Checking OpenTofu formatting..."
	@tofu fmt -check -recursive

lint: ## Run TFLint
	@echo "Linting Terraform..."
	@tflint --init
	@tflint --recursive --minimum-failure-severity=error

security: ## Run tfsec
	@echo "Running security scan..."
	@tfsec . --concise-output

quick: fmt-check validate lint ## Run fast local checks
	@echo "All fast checks passed."

docs: ## Regenerate root and module READMEs with terraform-docs
	@echo "Generating documentation..."
	@terraform-docs markdown table --output-file README.md .
	@find modules -name main.tf -type f | sort | while read file; do \
		dir=$$(dirname "$$file"); \
		echo "Generating docs for $$dir"; \
		terraform-docs markdown table --output-file README.md "$$dir"; \
	done

sync-metadata: ## Sync release-facing metadata from the monorepo root VERSION
	@cd .. && mise exec -- go run ./cmd/releasectl metadata sync

test: test-plan ## Run plan-only tests

test-plan: ## Run plan-only validation tests (free, ~2min)
	@echo "Running TestPlan*..."
	$(TEST_GO) test -v -timeout 15m -run "TestPlan" ./...

test-basic: ## Run basic infrastructure scenario (~45min, requires AWS + RUNS_ON_LICENSE_KEY)
	@echo "Running TestScenarioBasic..."
	$(TEST_GO) test -v -timeout 45m -run "TestScenarioBasic" ./...

test-basic-ci-image: ## Build/push a runs-on-ci image, export test vars, then run TestScenarioBasic
	@echo "Running TestScenarioBasic with a fresh runs-on-ci image..."
	$(TEST_WITH_CI_IMAGE) --scenario basic -- make -C terraform test-basic

test-private: ## Run private networking scenario (~60min, requires NAT gateway)
	@echo "Running TestScenarioPrivateNetworking..."
	$(TEST_GO) test -v -timeout 60m -run "TestScenarioPrivateNetworking" ./...

test-private-ci-image: ## Build/push a runs-on-ci image, export test vars, then run TestScenarioPrivateNetworking
	@echo "Running TestScenarioPrivateNetworking with a fresh runs-on-ci image..."
	$(TEST_WITH_CI_IMAGE) --scenario private -- make -C terraform test-private

test-full: ## Run full-featured scenario with EFS+ECR+NAT (~90min)
	@echo "Running TestScenarioFullFeatured..."
	$(TEST_GO) test -v -timeout 90m -run "TestScenarioFullFeatured" ./...

test-full-ci-image: ## Build/push a runs-on-ci image, export test vars, then run TestScenarioFullFeatured
	@echo "Running TestScenarioFullFeatured with a fresh runs-on-ci image..."
	$(TEST_WITH_CI_IMAGE) --scenario full -- make -C terraform test-full

test-integration: ## Run end-to-end integration test (~60min, requires GitHub App credentials)
	@echo "Running TestIntegrationEndToEnd..."
	$(TEST_GO) test -v -timeout 60m -run "TestIntegrationEndToEnd" ./...

test-integration-ci-image: ## Build/push a runs-on-ci image, export test vars, then run TestIntegrationEndToEnd
	@echo "Running TestIntegrationEndToEnd with a fresh runs-on-ci image..."
	$(TEST_WITH_CI_IMAGE) --scenario integration -- make -C terraform test-integration

test-short: ## Run all tests, skip expensive NAT-dependent scenarios
	@echo "Running short tests..."
	$(TEST_GO) test -v -short -timeout 60m ./...

test-all: ## Run all test scenarios (expensive, ~120min)
	@echo "Running all test scenarios..."
	$(TEST_GO) test -v -timeout 120m ./...

dev-vpc: ## Deploy dev VPC (run once, then use dev-apply)
	@echo "Deploying dev VPC (stack: $(DEV_STACK_NAME))..."
	@cd $(DEV_VPC_DIR) && tofu init -upgrade && tofu apply -auto-approve \
		-var="test_id=$(DEV_STACK_NAME)" \
		-var="enable_nat=$$(grep -q 'private_mode' $(CURDIR)/$(DEV_TFVARS) 2>/dev/null && grep 'private_mode' $(CURDIR)/$(DEV_TFVARS) | grep -qv '"false"' && echo true || echo false)"
	@echo ""
	@echo "VPC ready. Now run: make dev-apply"

dev-apply: ## Deploy RunsOn root module on the dev VPC
	@if [ ! -f "$(DEV_TFVARS)" ]; then \
		echo "Error: $(DEV_TFVARS) not found."; \
		echo "Copy dev.tfvars.example to dev.tfvars and fill in your values."; \
		exit 1; \
	fi
	@echo "Deploying RunsOn (stack: $$(grep stack_name $(DEV_TFVARS) | head -1 | sed 's/.*= *"\(.*\)"/\1/'))..."
	@tofu init -upgrade
	tofu apply \
		-var-file="$(DEV_TFVARS)" \
		-var="vpc_id=$$(cd $(DEV_VPC_DIR) && tofu output -raw vpc_id)" \
		-var="public_subnet_ids=$$(cd $(DEV_VPC_DIR) && tofu output -json public_subnets)" \
		-var="private_subnet_ids=$$(cd $(DEV_VPC_DIR) && tofu output -json private_subnets)"

dev-destroy: ## Destroy RunsOn and the dev VPC
	@echo "Destroying RunsOn..."
	-tofu destroy \
		-var-file="$(DEV_TFVARS)" \
		-var="vpc_id=$$(cd $(DEV_VPC_DIR) && tofu output -raw vpc_id)" \
		-var="public_subnet_ids=$$(cd $(DEV_VPC_DIR) && tofu output -json public_subnets)" \
		-var="private_subnet_ids=$$(cd $(DEV_VPC_DIR) && tofu output -json private_subnets)"
	@echo "Destroying dev VPC..."
	cd $(DEV_VPC_DIR) && tofu destroy -auto-approve \
		-var="test_id=$(DEV_STACK_NAME)"

dev-output: ## Show dev deployment outputs
	@tofu output

clean: ## Remove local OpenTofu state and cache directories
	@echo "Cleaning up..."
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.tfstate*" -delete 2>/dev/null || true
	@find . -type f -name "tfplan" -delete 2>/dev/null || true

check: ## Validate version format against root release tags
	@if ! echo "$(VERSION)" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$$'; then \
		echo "Error: VERSION must be format vX.Y.Z (e.g., v2.12.1)"; \
		exit 1; \
	fi
	@echo "Version $(VERSION) is valid"
