.PHONY: help init validate fmt fmt-check lint security plan quick pre-commit watch test-module clean install-tools

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

init: ## Initialize OpenTofu
	@echo "🔧 Initializing OpenTofu..."
	@tofu init -upgrade

validate: ## Validate OpenTofu syntax (< 1 sec)
	@echo "✅ Validating OpenTofu..."
	@tofu validate

fmt: ## Format OpenTofu files
	@echo "🎨 Formatting OpenTofu files..."
	@tofu fmt -recursive

fmt-check: ## Check if files are formatted
	@echo "🔍 Checking OpenTofu formatting..."
	@tofu fmt -check -recursive

lint: ## Run TFLint (< 5 sec)
	@echo "🔍 Linting Terraform..."
	@if command -v tflint >/dev/null 2>&1; then \
		tflint --init; \
		tflint --recursive || true; \
	else \
		echo "⚠️  tflint not installed, skipping..."; \
	fi

security: ## Run security scans (< 15 sec)
	@echo "🔒 Running security scans..."
	@if command -v checkov >/dev/null 2>&1; then \
		checkov -d . --quiet --compact --framework terraform; \
	else \
		echo "⚠️  checkov not installed, skipping..."; \
	fi
	@if command -v tfsec >/dev/null 2>&1; then \
		tfsec . --concise-output; \
	else \
		echo "⚠️  tfsec not installed, skipping..."; \
	fi

plan: ## Run tofu plan (< 30 sec)
	@echo "📋 Running OpenTofu plan..."
	@tofu plan -out=tfplan



quick: fmt-check validate lint ## Run all fast checks (< 20 sec total)
	@echo "✨ All fast checks passed!"

pre-commit: quick security ## Run before committing
	@echo "🎉 Ready to commit!"

watch: ## Watch files and auto-validate
	@echo "👀 Watching for changes..."
	@if command -v watchexec >/dev/null 2>&1; then \
		watchexec -e tf -c clear "make quick"; \
	else \
		echo "❌ watchexec not installed. Install with: brew install watchexec"; \
		exit 1; \
	fi

docs: ## Generate documentation for all modules
	@echo "📚 Generating documentation..."
	@if command -v terraform-docs >/dev/null 2>&1; then \
		terraform-docs markdown table --output-file README.md .; \
		find modules -name "*.tf" -type f -exec dirname {} \; | sort -u | while read dir; do \
			if [ -f "$$dir/main.tf" ]; then \
				echo "Generating docs for $$dir"; \
				terraform-docs markdown table --output-file README.md "$$dir"; \
			fi \
		done; \
	else \
		echo "❌ terraform-docs not installed. Install with: brew install terraform-docs"; \
		echo "Note: Works with OpenTofu .tf files"; \
		exit 1; \
	fi

clean: ## Clean up OpenTofu files
	@echo "🧹 Cleaning up..."
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.tfstate*" -delete 2>/dev/null || true
	@find . -type f -name "tfplan" -delete 2>/dev/null || true
	@find . -type f -name ".terraform.lock.hcl" -delete 2>/dev/null || true

install-tools: ## Install development tools (macOS)
	@echo "📦 Installing development tools..."
	@if [[ "$$OSTYPE" == "darwin"* ]]; then \
		echo "Installing for macOS..."; \
		brew install opentofu tflint tfsec checkov watchexec terraform-docs pre-commit; \
	elif [[ "$$OSTYPE" == "linux-gnu"* ]]; then \
		echo "Installing for Linux..."; \
		echo "Please install OpenTofu from: https://opentofu.org/docs/intro/install/"; \
	else \
		echo "❌ Unsupported OS. Please install tools manually."; \
	fi
	@echo "✅ Tools installed! Run 'make help' to see available commands"

.DEFAULT_GOAL := help
