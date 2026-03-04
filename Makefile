# Version for this terraform module (follows RunsOn version with -rN suffix)
# e.g., v2.11.0-r1 means compatible with RunsOn v2.11.0, terraform revision 1
VERSION=v2.11.0-r1

.PHONY: help init validate fmt fmt-check lint security quick pre-commit docs clean install-tools test test-short test-all test-basic test-full \
	check pre-release tag release

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

pre-commit: quick security ## Run before committing
	@echo "Ready to commit!"

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

test: test-basic ## Run basic test scenario (alias for test-basic)

test-short: ## Run tests, skip expensive scenarios
	@echo "Running short tests..."
	cd test && mise exec -- go test -v -short ./...

test-all: ## Run all test scenarios (expensive)
	@echo "Running all test scenarios..."
	cd test && mise exec -- go test -v -timeout 120m ./...

test-basic: ## Run basic test scenario
	@echo "Running TestScenarioBasic..."
	cd test && mise exec -- go test -v -timeout 45m -run "TestScenarioBasic" ./...

test-full: ## Run full-featured test scenario (expensive)
	@echo "Running TestScenarioFullFeatured..."
	cd test && mise exec -- go test -v -timeout 90m -run "TestScenarioFullFeatured" ./...

clean: ## Clean up OpenTofu files
	@echo "Cleaning up..."
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.tfstate*" -delete 2>/dev/null || true
	@find . -type f -name "tfplan" -delete 2>/dev/null || true
	@find . -type f -name ".terraform.lock.hcl" -delete 2>/dev/null || true

install-tools: ## Install development tools (macOS)
	@echo "Installing development tools..."
	@if [ "$$(uname)" = "Darwin" ]; then \
		echo "Installing for macOS..."; \
		brew install opentofu tflint tfsec terraform-docs; \
	else \
		echo "Linux: Please install OpenTofu from https://opentofu.org/docs/intro/install/"; \
		echo "Then install tflint, tfsec, and terraform-docs manually."; \
	fi

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

tag: pre-release check ## Create git tag for release
	git tag -m "$(VERSION)" "$(VERSION)"

release: ## Push tags and create GitHub release
	git push origin --tags
	gh release create $(VERSION) --generate-notes --draft
	@echo ""
	@echo "Draft release created for $(VERSION)"
	@echo "Review and publish at: https://github.com/runs-on/terraform-aws-runs-on/releases"
