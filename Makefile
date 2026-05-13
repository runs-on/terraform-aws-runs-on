VERSION ?= $(shell if [ -f ../VERSION ]; then tr -d '\n' < ../VERSION; elif [ -f VERSION ]; then tr -d '\n' < VERSION; elif git describe --tags --exact-match >/dev/null 2>&1; then git describe --tags --exact-match; else echo dev; fi)

# Dev deploy config
DEV_VPC_DIR = modules/flex/test/fixtures/vpc
DEV_TFVARS = dev.tfvars
DEV_STACK_NAME ?= runs-on-tf
TEST_GO = cd modules/flex/test && mise exec -- go
TEST_WITH_CI_IMAGE = $(TEST_GO) run ./cmd/with-ci-image
TEST_PLAN_LOCK_FILE ?= modules/flex/.terraform.lock.hcl
TEST_PLAN_MIN_AWS_LOCK_FILE = testdata/provider-locks/aws-6.33/.terraform.lock.hcl
TEST_PLAN_TOFU_MODULES = \
	modules/flex \
	modules/control_plane/flex \
	modules/control_plane/runtime \
	modules/runner/compute \
	modules/runner/extras \
	modules/runner/network
TEST_PLAN_GO_PATTERN = TestPlanSource

.PHONY: help init validate fmt fmt-check lint quick docs clean sync-metadata \
	test test-plan test-plan-tofu test-plan-source test-plan-min-aws-provider \
	test-basic test-private test-full test-integration test-short test-all \
	test-basic-ci-image test-private-ci-image test-full-ci-image test-integration-ci-image \
	dev-vpc dev-apply dev-destroy dev-output \
	check

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

init: ## Initialize OpenTofu
	@echo "Initializing OpenTofu..."
	@cd modules/flex && tofu init -upgrade
	@cd modules/fleet && tofu init -upgrade

validate: ## Validate OpenTofu syntax
	@echo "Validating OpenTofu..."
	@cd modules/flex && tofu validate
	@cd modules/fleet && tofu validate

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

quick: fmt-check validate lint ## Run fast local checks
	@echo "All fast checks passed."

docs: ## Regenerate root and module READMEs with terraform-docs
	@echo "Generating documentation..."
	@find modules -name main.tf -type f ! -path '*/internal/*' ! -path '*/.terraform/*' ! -path '*/examples/*' ! -path '*/test/*' | sort | while read file; do \
		dir=$$(dirname "$$file"); \
		echo "Generating docs for $$dir"; \
		(cd "$$dir" && terraform-docs --config "$(CURDIR)/.terraform-docs.yml" markdown table --output-file README.md .); \
	done

sync-metadata: ## Sync release-facing metadata from the monorepo root VERSION
	@cd .. && mise exec -- go run ./cmd/releasectl metadata sync

test: test-plan ## Run plan-only tests

test-plan: ## Run plan-only validation tests (free, ~2min)
	$(MAKE) test-plan-tofu
	$(MAKE) test-plan-source

test-plan-tofu:
	@echo "Running OpenTofu plan tests..."
	@tmp=$$(mktemp -d); \
		set -e; \
		trap 'rm -rf "$$tmp"' EXIT; \
		lock_versions="$$tmp/provider-versions"; \
		awk '/^provider "/ { provider=$$2; gsub(/"/, "", provider) } /version[[:space:]]*=/ { version=$$3; gsub(/"/, "", version); print provider " " version }' "$(TEST_PLAN_LOCK_FILE)" > "$$lock_versions"; \
		rsync -a --exclude '.terraform/' --exclude '.terraform.lock.hcl' modules "$$tmp/"; \
		cp -R lambdas "$$tmp/lambdas"; \
		for dir in $(TEST_PLAN_TOFU_MODULES); do \
			echo "Running tofu test in $$dir"; \
			cp "$(TEST_PLAN_LOCK_FILE)" "$$tmp/$$dir/.terraform.lock.hcl"; \
			(cd "$$tmp/$$dir" && \
				tofu init -backend=false -input=false >/dev/null && \
				awk '/^provider "/ { provider=$$2; gsub(/"/, "", provider) } /version[[:space:]]*=/ { version=$$3; gsub(/"/, "", version); print provider " " version }' .terraform.lock.hcl > .terraform/provider-versions && \
				while read provider version; do \
					grep -qx "$$provider $$version" "$$lock_versions" || { echo "$$dir selected $$provider $$version, which is not pinned by $(TEST_PLAN_LOCK_FILE)"; exit 1; }; \
				done < .terraform/provider-versions && \
				tofu init -backend=false -input=false -lockfile=readonly >/dev/null && \
				tofu test -no-color); \
		done

test-plan-source:
	@echo "Running source-level plan checks..."
	$(TEST_GO) test -v -timeout 15m -run $(TEST_PLAN_GO_PATTERN) ./...

test-plan-min-aws-provider: ## Run native plan tests against the minimum supported AWS provider
	$(MAKE) test-plan-tofu TEST_PLAN_LOCK_FILE=$(TEST_PLAN_MIN_AWS_LOCK_FILE)

test-basic: ## Run basic infrastructure scenario (~45min, requires AWS + RUNS_ON_LICENSE_KEY)
	@echo "Running TestScenarioMatrix/basic..."
	$(TEST_GO) test -v -timeout 45m -run "TestScenarioMatrix/basic" ./...

test-basic-ci-image: ## Build/push a runs-on-ci image, export test vars, then run the basic scenario matrix case
	@echo "Running TestScenarioMatrix/basic with a fresh runs-on-ci image..."
	$(TEST_WITH_CI_IMAGE) --scenario basic -- make -C terraform test-basic

test-private: ## Run private networking scenario (~60min, requires NAT gateway)
	@echo "Running TestScenarioMatrix/private..."
	$(TEST_GO) test -v -timeout 60m -run "TestScenarioMatrix/private" ./...

test-private-ci-image: ## Build/push a runs-on-ci image, export test vars, then run the private scenario matrix case
	@echo "Running TestScenarioMatrix/private with a fresh runs-on-ci image..."
	$(TEST_WITH_CI_IMAGE) --scenario private -- make -C terraform test-private

test-full: ## Run full-featured scenario with EFS+ECR+NAT (~90min)
	@echo "Running TestScenarioMatrix/full..."
	$(TEST_GO) test -v -timeout 90m -run "TestScenarioMatrix/full" ./...

test-full-ci-image: ## Build/push a runs-on-ci image, export test vars, then run the full scenario matrix case
	@echo "Running TestScenarioMatrix/full with a fresh runs-on-ci image..."
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

dev-apply: ## Deploy RunsOn Flex on the dev VPC
	@if [ ! -f "$(DEV_TFVARS)" ]; then \
		echo "Error: $(DEV_TFVARS) not found."; \
		echo "Copy dev.tfvars.example to dev.tfvars and fill in your values."; \
		exit 1; \
	fi
	@echo "Deploying RunsOn Flex (stack: $$(grep stack_name $(DEV_TFVARS) | head -1 | sed 's/.*= *"\(.*\)"/\1/'))..."
	@cd modules/flex && tofu init -upgrade
	cd modules/flex && tofu apply \
		-var-file="$(CURDIR)/$(DEV_TFVARS)" \
		-var="vpc_id=$$(cd $(CURDIR)/$(DEV_VPC_DIR) && tofu output -raw vpc_id)" \
		-var="public_subnet_ids=$$(cd $(CURDIR)/$(DEV_VPC_DIR) && tofu output -json public_subnets)" \
		-var="private_subnet_ids=$$(cd $(CURDIR)/$(DEV_VPC_DIR) && tofu output -json private_subnets)"

dev-destroy: ## Destroy RunsOn Flex and the dev VPC
	@echo "Destroying RunsOn Flex..."
	-cd modules/flex && tofu destroy \
		-var-file="$(CURDIR)/$(DEV_TFVARS)" \
		-var="vpc_id=$$(cd $(CURDIR)/$(DEV_VPC_DIR) && tofu output -raw vpc_id)" \
		-var="public_subnet_ids=$$(cd $(CURDIR)/$(DEV_VPC_DIR) && tofu output -json public_subnets)" \
		-var="private_subnet_ids=$$(cd $(CURDIR)/$(DEV_VPC_DIR) && tofu output -json private_subnets)"
	@echo "Destroying dev VPC..."
	cd $(DEV_VPC_DIR) && tofu destroy -auto-approve \
		-var="test_id=$(DEV_STACK_NAME)"

dev-output: ## Show dev deployment outputs
	@cd modules/flex && tofu output

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
