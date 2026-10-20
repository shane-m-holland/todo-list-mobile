# Container runtime: podman by default, override with `make CONTAINER=docker ...`
CONTAINER ?= podman

SPECTRAL_IMAGE ?= docker.io/stoplight/spectral:6
REDOCLY_IMAGE  ?= docker.io/redocly/cli:latest

CONTRACT := contract/openapi.yaml

.DEFAULT_GOAL := help

.PHONY: help
help: ## List available targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# --- Contract ----------------------------------------------------------------

.PHONY: lint-contract
lint-contract: ## Lint the OpenAPI contract with Spectral
	$(CONTAINER) run --rm -v "$(CURDIR)/contract:/work:ro" -w /work $(SPECTRAL_IMAGE) \
		lint openapi.yaml --ruleset .spectral.yaml --fail-severity warn

.PHONY: contract-docs
contract-docs: ## Render the contract to build/contract/index.html (Redoc)
	@mkdir -p build/contract
	$(CONTAINER) run --rm -v "$(CURDIR):/work" -w /work $(REDOCLY_IMAGE) \
		build-docs $(CONTRACT) --output build/contract/index.html
	@echo "Open build/contract/index.html"
