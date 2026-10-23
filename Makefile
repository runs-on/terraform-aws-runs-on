TEST_GO = cd modules/flex/test && mise exec go -- go
TEST_WITH_CI_IMAGE = $(TEST_GO) run ./cmd/with-ci-image
TEST_PLAN_LOCK_FILE ?= modules/flex/.terraform.lock.hcl
TEST_PLAN_MIN_AWS_LOCK_FILE = testdata/provider-locks/aws-6.45/.terraform.lock.hcl
TEST_PLAN_PLUGIN_CACHE_DIR ?= $(CURDIR)/.terraform/plugin-cache
TEST_PLAN_TOFU_MODULES = \
	modules/ami_sync \
	modules/flex \
	modules/fleet \
	modules/control_plane/alerts \
	modules/control_plane/control_plane_fleet \
	modules/control_plane/control_plane_flex \
	modules/control_plane/github_platform \
	modules/control_plane/runtime \
	modules/runner/compute \
	modules/runner/extras \
	modules/runner/network
# The live scenarios deploy real stacks; everything else in the harness module
# (plan checks and the harness's own unit tests) runs in CI.
TEST_LIVE_GO_PATTERN = ^(TestScenarioMatrix|TestIntegrationEndToEnd)$$

.PHONY: help init validate fmt fmt-check lint quick docs clean sync-metadata \
	test test-plan test-plan-tofu test-plan-source test-plan-min-aws-provider \
	test-basic test-private test-full test-integration \
	test-basic-ci-image test-private-ci-image test-full-ci-image test-integration-ci-image

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

init: ## Initialize OpenTofu
	@echo "Initializing OpenTofu..."
	@cd modules/flex && tofu init
	@cd modules/fleet && tofu init

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
	@find modules -name main.tf -type f ! -path '*/internal/*' ! -path '*/.terraform/*' ! -path '*/examples/*' ! -path '*/test/*' ! -path '*/tests/*' | sort | while read file; do \
		dir=$$(dirname "$$file"); \
		echo "Generating docs for $$dir"; \
		(cd "$$dir" && terraform-docs --config "$(CURDIR)/.terraform-docs.yml" markdown table --output-file README.md .); \
	done

sync-metadata: ## Sync release-facing metadata from the monorepo root VERSION
	@cd .. && mise exec go -- go run ./cmd/releasectl metadata sync

test: test-plan ## Run plan-only tests

test-plan: ## Run plan-only validation tests (free, ~2min)
	$(MAKE) test-plan-tofu
	$(MAKE) test-plan-source

# Each module may rewrite lockfile constraint metadata, so initialize once and
# verify that every selected provider version still comes from the canonical
# lockfile. A second read-only init would only repeat the same installation.
# Validating here also covers modules without test files, such as ami_sync.
test-plan-tofu:
	@echo "Running OpenTofu plan tests..."
	@tmp=$$(mktemp -d); \
		cache_dir="$${TF_PLUGIN_CACHE_DIR:-$(TEST_PLAN_PLUGIN_CACHE_DIR)}"; \
		set -e; \
		mkdir -p "$$cache_dir"; \
		export TF_PLUGIN_CACHE_DIR="$$cache_dir"; \
		export TOFU_PLUGIN_CACHE_DIR="$${TOFU_PLUGIN_CACHE_DIR:-$$cache_dir}"; \
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
				awk '/^provider "/ { provider=$$2; gsub(/"/, "", provider) } /version[[:space:]]*=/ { version=$$3; gsub(/"/, "", version); print provider " " version }' .terraform.lock.hcl > "$$tmp/selected-versions" && \
				while read provider version; do \
					grep -qx "$$provider $$version" "$$lock_versions" || { echo "$$dir selected $$provider $$version, which is not pinned by $(TEST_PLAN_LOCK_FILE)"; exit 1; }; \
				done < "$$tmp/selected-versions" && \
				tofu validate -no-color && \
				tofu test -no-color); \
		done

test-plan-source:
	@echo "Running Go structured plan checks and harness tests..."
	@set -e; \
		cache_dir="$${TF_PLUGIN_CACHE_DIR:-$(TEST_PLAN_PLUGIN_CACHE_DIR)}"; \
		mkdir -p "$$cache_dir"; \
		export TF_PLUGIN_CACHE_DIR="$$cache_dir"; \
		export TOFU_PLUGIN_CACHE_DIR="$${TOFU_PLUGIN_CACHE_DIR:-$$cache_dir}"; \
		$(TEST_GO) test -v -timeout 15m -skip '$(TEST_LIVE_GO_PATTERN)' ./...

test-plan-min-aws-provider: ## Run native plan tests against the minimum supported AWS provider
	$(MAKE) test-plan-tofu TEST_PLAN_LOCK_FILE=$(TEST_PLAN_MIN_AWS_LOCK_FILE)

# Live scenarios test only the harness package: in package-list mode (./...)
# go test buffers each package's output until it exits, so a killed or timed
# out run would print nothing. The CI targets (basic, integration) time out at
# ~2.5x their slowest recent run; an interrupted run no longer leaks its stack
# (see tools/terratest-janitor).
test-basic: ## Run basic infrastructure scenario (~10min, requires AWS + RUNS_ON_LICENSE_KEY)
	@echo "Running TestScenarioMatrix/basic..."
	$(TEST_GO) test -v -timeout 25m -run "TestScenarioMatrix/basic" .

test-basic-ci-image: ## Build/push a runs-on-ci image, export test vars, then run the basic scenario matrix case
	@echo "Running TestScenarioMatrix/basic with a fresh runs-on-ci image..."
	$(TEST_WITH_CI_IMAGE) --scenario basic -- make -C terraform test-basic

test-private: ## Run private networking scenario (~60min, requires NAT gateway)
	@echo "Running TestScenarioMatrix/private..."
	$(TEST_GO) test -v -timeout 60m -run "TestScenarioMatrix/private" .

test-private-ci-image: ## Build/push a runs-on-ci image, export test vars, then run the private scenario matrix case
	@echo "Running TestScenarioMatrix/private with a fresh runs-on-ci image..."
	$(TEST_WITH_CI_IMAGE) --scenario private -- make -C terraform test-private

test-full: ## Run full-featured scenario with EFS+ECR+NAT (~90min)
	@echo "Running TestScenarioMatrix/full..."
	$(TEST_GO) test -v -timeout 90m -run "TestScenarioMatrix/full" .

test-full-ci-image: ## Build/push a runs-on-ci image, export test vars, then run the full scenario matrix case
	@echo "Running TestScenarioMatrix/full with a fresh runs-on-ci image..."
	$(TEST_WITH_CI_IMAGE) --scenario full -- make -C terraform test-full

test-integration: ## Run end-to-end integration test (~10min, requires GitHub App credentials)
	@echo "Running TestIntegrationEndToEnd..."
	$(TEST_GO) test -v -timeout 30m -run "TestIntegrationEndToEnd" .

test-integration-ci-image: ## Build/push a runs-on-ci image, export test vars, then run TestIntegrationEndToEnd
	@echo "Running TestIntegrationEndToEnd with a fresh runs-on-ci image..."
	$(TEST_WITH_CI_IMAGE) --scenario integration -- make -C terraform test-integration

clean: ## Remove local OpenTofu state and cache directories
	@echo "Cleaning up..."
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.tfstate*" -delete 2>/dev/null || true
	@find . -type f -name "tfplan" -delete 2>/dev/null || true
