# Container runtime: podman by default, override with `make CONTAINER=docker ...`
CONTAINER ?= podman

SPECTRAL_IMAGE ?= docker.io/stoplight/spectral:6
REDOCLY_IMAGE  ?= docker.io/redocly/cli:latest

CONTRACT := contract/openapi.yaml

COMPOSE  ?= $(CONTAINER) compose -f mock/compose.yaml
MOCK_URL ?= http://localhost:8080
MOCK_DELAY_MS ?= 2000

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

# --- Mock API (WireMock) -----------------------------------------------------

.PHONY: mock-up
mock-up: ## Build and start the WireMock mock on :8080, then seed it
	$(COMPOSE) up -d --build
	@printf "Waiting for WireMock"; for i in $$(seq 1 30); do \
		curl -fsS $(MOCK_URL)/__admin/health >/dev/null 2>&1 && break; printf "."; sleep 1; done; echo
	@MOCK_URL=$(MOCK_URL) mock/seed.sh

.PHONY: mock-down
mock-down: ## Stop and remove the mock container
	$(COMPOSE) down

.PHONY: mock-logs
mock-logs: ## Follow mock container logs
	$(COMPOSE) logs -f

.PHONY: mock-reset
mock-reset: ## Clear mock state and re-seed sample todos
	@MOCK_URL=$(MOCK_URL) mock/seed.sh

.PHONY: mock-smoke
mock-smoke: ## Run the CRUD smoke test against the mock
	@BASE_URL=$(MOCK_URL)/api/v1 mock/smoke.sh

.PHONY: mock-fail-on
mock-fail-on: ## Make every API call return 500
	@curl -fsS -o /dev/null -X PUT $(MOCK_URL)/__admin/scenarios/failure-mode/state -d '{"state":"failing"}'
	@echo "Failure mode ON: /api/v1/* returns 500"

.PHONY: mock-fail-off
mock-fail-off: ## Return to normal responses
	@curl -fsS -o /dev/null -X PUT $(MOCK_URL)/__admin/scenarios/failure-mode/state
	@echo "Failure mode OFF"

.PHONY: mock-slow
mock-slow: ## Add a global response delay (MOCK_DELAY_MS, default 2000)
	@curl -fsS -o /dev/null -X POST $(MOCK_URL)/__admin/settings -d '{"fixedDelay":$(MOCK_DELAY_MS)}'
	@echo "Responses delayed by $(MOCK_DELAY_MS) ms"

.PHONY: mock-fast
mock-fast: ## Remove the global response delay
	@curl -fsS -o /dev/null -X POST $(MOCK_URL)/__admin/settings -d '{"fixedDelay":0}'
	@echo "Response delay removed"

# --- Android -----------------------------------------------------------------

# Gradle needs JDK 17+; 21 is the tested version. Override for a non-Homebrew JDK.
JDK21_HOME ?= /opt/homebrew/opt/openjdk@21
GRADLE := cd android && JAVA_HOME=$(JDK21_HOME) ./gradlew --console=plain
ANDROID_SDK ?= $(or $(ANDROID_HOME),$(HOME)/Library/Android/sdk)
ADB ?= $(ANDROID_SDK)/platform-tools/adb

.PHONY: android-build
android-build: ## Assemble the mockDebug APK (regenerates the API client from the contract)
	$(GRADLE) :app:assembleMockDebug

.PHONY: android-test
android-test: ## Run Android unit tests (network module + app repository)
	$(GRADLE) :core:network:test :app:testMockDebugUnitTest

.PHONY: android-ui-test
android-ui-test: ## Run Compose UI tests on the running emulator
	$(GRADLE) :app:connectedMockDebugAndroidTest

.PHONY: android-install
android-install: ## Install and launch mockDebug on the running emulator
	$(GRADLE) :app:installMockDebug
	$(ADB) shell am start -n com.example.todo.mock/com.example.todo.MainActivity
