# Version for this terraform module (follows RunsOn version with -rN suffix)
# e.g., v2.11.0-r1 means compatible with RunsOn v2.11.0, terraform revision 1
VERSION=v2.12.0-r1
REGISTRY=public.ecr.aws/c5h5o9k1/runs-on/runs-on
APP_VERSION=$(shell echo $(VERSION) | sed 's/-r[0-9]*//')

# Dev deploy config
DEV_VPC_DIR=test/fixtures/vpc
DEV_TFVARS=dev.tfvars
DEV_STACK_NAME ?= runs-on-tf

.PHONY: help init validate fmt fmt-check lint security quick docs clean \
	test test-plan test-basic test-private test-full test-integration test-short test-all \
	dev-vpc dev-apply dev-destroy dev-output \
	image-sync image-check readme-sync check pre-release tag release

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

fmt-check: ## Check if files are formatted
	@echo "Checking OpenTofu formatting..."
	@tofu fmt -check -recursive

lint: ## Run TFLint
	@echo "Linting Terraform..."
	@if command -v tflint >/dev/null 2>&1; then \
		tflint --init; \
		tflint --recursive || true; \
	else \
		echo "tflint not installed, skipping..."; \
	fi

security: ## Run tfsec security scan
	@echo "Running security scan..."
	@if command -v tfsec >/dev/null 2>&1; then \
		tfsec . --concise-output; \
	else \
		echo "tfsec not installed, skipping..."; \
	fi

quick: fmt-check validate lint ## Run all fast checks
	@echo "All fast checks passed!"

docs: ## Generate documentation for all modules
	@echo "Generating documentation..."
	@if command -v terraform-docs >/dev/null 2>&1; then \
		terraform-docs markdown table --output-file README.md .; \
		find modules -name "*.tf" -type f -exec dirname {} \; | sort -u | while read dir; do \
			if [ -f "$$dir/main.tf" ]; then \
				echo "Generating docs for $$dir"; \
				terraform-docs markdown table --output-file README.md "$$dir"; \
			fi \
		done; \
	else \
		echo "terraform-docs not installed. Install with: brew install terraform-docs"; \
		exit 1; \
	fi

test: test-plan ## Run plan tests (free, no AWS resources)

test-plan: ## Run plan-only validation tests (free, ~2min)
	@echo "Running TestPlan*..."
	cd test && mise exec -- go test -v -timeout 15m -run "TestPlan" ./...

test-basic: ## Run basic infrastructure scenario (~45min, requires AWS + RUNS_ON_LICENSE_KEY)
	@echo "Running TestScenarioBasic..."
	cd test && mise exec -- go test -v -timeout 45m -run "TestScenarioBasic" ./...

test-private: ## Run private networking scenario (~60min, requires NAT gateway)
	@echo "Running TestScenarioPrivateNetworking..."
	cd test && mise exec -- go test -v -timeout 60m -run "TestScenarioPrivateNetworking" ./...

test-full: ## Run full-featured scenario with EFS+ECR+NAT (~90min)
	@echo "Running TestScenarioFullFeatured..."
	cd test && mise exec -- go test -v -timeout 90m -run "TestScenarioFullFeatured" ./...

test-integration: ## Run end-to-end integration test (~60min, requires GitHub App credentials)
	@echo "Running TestIntegrationEndToEnd..."
	cd test && mise exec -- go test -v -timeout 60m -run "TestIntegrationEndToEnd" ./...

test-short: ## Run all tests, skip expensive NAT-dependent scenarios
	@echo "Running short tests..."
	cd test && mise exec -- go test -v -short -timeout 60m ./...

test-all: ## Run all test scenarios (expensive, ~120min)
	@echo "Running all test scenarios..."
	cd test && mise exec -- go test -v -timeout 120m ./...

dev-vpc: ## Deploy dev VPC (run once, then use dev-apply)
	@echo "Deploying dev VPC (stack: $(DEV_STACK_NAME))..."
	@cd $(DEV_VPC_DIR) && tofu init -upgrade && tofu apply -auto-approve \
		-var="test_id=$(DEV_STACK_NAME)" \
		-var="enable_nat=$$(grep -q 'private_mode' $(CURDIR)/$(DEV_TFVARS) 2>/dev/null && grep 'private_mode' $(CURDIR)/$(DEV_TFVARS) | grep -qv '"false"' && echo true || echo false)"
	@echo ""
	@echo "VPC ready. Now run: make dev-apply"

dev-apply: ## Deploy RunsOn root module on dev VPC
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

dev-destroy: ## Destroy RunsOn and dev VPC
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

clean: ## Clean up OpenTofu files
	@echo "Cleaning up..."
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.tfstate*" -delete 2>/dev/null || true
	@find . -type f -name "tfplan" -delete 2>/dev/null || true
	@find . -type f -name ".terraform.lock.hcl" -delete 2>/dev/null || true

image-sync: ## Sync app_image and app_tag defaults to match VERSION
	@IMAGE_REF="$(REGISTRY):$(APP_VERSION)" && \
	echo "Resolving digest for $$IMAGE_REF..." && \
	DIGEST=$$(docker buildx imagetools inspect "$$IMAGE_REF" --format '{{json .}}' 2>/dev/null | jq -r '.manifest.digest // empty' || echo "") && \
	if [ -z "$$DIGEST" ]; then \
		echo "Error: Could not resolve digest for $$IMAGE_REF"; \
		exit 1; \
	fi && \
	FULL_IMAGE="$(REGISTRY):$(APP_VERSION)@$$DIGEST" && \
	echo "Updating app_image to $$FULL_IMAGE" && \
	sed -i.bak 's|default *= *"public.ecr.aws/c5h5o9k1/runs-on/runs-on:[^"]*"|default     = "'$$FULL_IMAGE'"|' variables.tf && \
	rm -f variables.tf.bak && \
	sed -i.bak '/variable "app_tag"/,/^}/{s|default *= *"[^"]*"|default     = "$(APP_VERSION)"|;}' variables.tf && \
	rm -f variables.tf.bak && \
	echo "✓ app_image: $$FULL_IMAGE" && \
	echo "✓ app_tag: $(APP_VERSION)"

image-check: ## Verify app_image is not pointing to dev
	@IMAGE=$$(grep -A3 'variable "app_image"' variables.tf | grep default | sed 's/.*"\(.*\)"/\1/') && \
	if echo "$$IMAGE" | grep -q ':dev@'; then \
		echo "Error: app_image still points to dev. Run 'make image-sync' first."; \
		exit 1; \
	fi && \
	echo "✓ app_image: $$IMAGE"

check: ## Validate version format
	@if ! echo "$(VERSION)" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+-r[0-9]+$$'; then \
		echo "Error: VERSION must be format vX.Y.Z-rN (e.g., v2.11.0-r1)"; \
		exit 1; \
	fi
	@echo "Version $(VERSION) is valid"

pre-release: ## Check for uncommitted changes before release
	@if ! git diff-index --quiet HEAD --; then \
		echo "Error: You have uncommitted changes. Commit or stash them first."; \
		git status --short; \
		exit 1; \
	fi
	@if ! git diff-index --quiet --cached HEAD --; then \
		echo "Error: You have staged changes. Commit them first."; \
		git status --short; \
		exit 1; \
	fi

tag: pre-release check quick docs image-check readme-sync ## Create git tag for release
	git tag -m "$(VERSION)" "$(VERSION)"

release: ## Push tags and create GitHub release
	git push origin --tags
	gh release create $(VERSION) --generate-notes --draft
	@echo ""
	@echo "Draft release created for $(VERSION)"
	@echo "Review and publish at: https://github.com/runs-on/terraform-aws-runs-on/releases"

readme-sync: ## Update README.md version references to match VERSION
	@echo "Updating README.md version to $(VERSION)..."
	@sed -i.bak 's|version = "v[0-9]*\.[0-9]*\.[0-9]*-r[0-9]*"|version = "$(VERSION)"|g' README.md && \
	rm -f README.md.bak && \
	UPDATED=$$(grep -c 'version = "$(VERSION)"' README.md) && \
	echo "✓ Updated $$UPDATED version references in README.md"
