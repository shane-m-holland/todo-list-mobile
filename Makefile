# Container runtime: podman by default, override with `make CONTAINER=docker ...`
CONTAINER ?= podman

SPECTRAL_IMAGE ?= docker.io/stoplight/spectral:6
REDOCLY_IMAGE  ?= docker.io/redocly/cli:latest

CONTRACT := contract/openapi.yaml

COMPOSE  ?= $(CONTAINER) compose -f mock/compose.yaml
MOCK_URL ?= http://localhost:8080
MOCK_DELAY_MS ?= 2000

BACKEND_PORT ?= 8081
BACKEND_URL  ?= http://localhost:$(BACKEND_PORT)

.DEFAULT_GOAL := help

.PHONY: help
help: ## List available targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

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
	@BASE_URL=$(MOCK_URL)/api/v1 scripts/smoke.sh

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

# Which backend the app talks to: mock (WireMock :8080) or local (Spring Boot :8081).
ANDROID_FLAVOR ?= mock
FLAVOR_TASK = $(shell echo $(ANDROID_FLAVOR) | awk '{print toupper(substr($$0,1,1)) substr($$0,2)}')

.PHONY: android-build
android-build: ## Assemble the debug APK for ANDROID_FLAVOR=mock|local (regenerates the API client from the contract)
	$(GRADLE) :app:assemble$(FLAVOR_TASK)Debug

.PHONY: android-test
android-test: ## Run Android unit tests (network module, repository, view model)
	$(GRADLE) :core:network:test :app:testMockDebugUnitTest

.PHONY: android-ui-test
android-ui-test: ## Run Compose UI tests on the running emulator
	$(GRADLE) :app:connectedMockDebugAndroidTest

.PHONY: android-install
android-install: ## Install and launch the debug app on the running emulator (ANDROID_FLAVOR=mock|local)
	$(GRADLE) :app:install$(FLAVOR_TASK)Debug
	$(ADB) shell am start -n com.example.todo.$(ANDROID_FLAVOR)/com.example.todo.MainActivity

# --- Backend (Spring Boot) ---------------------------------------------------

# Testcontainers talks to the container runtime over its socket. Podman's isn't at the Docker
# default, so point DOCKER_HOST at it unless the caller already did. Ryuk (the cleanup sidecar)
# needs privileges rootless Podman doesn't give it; the tests stop their own containers.
TC_SOCKET = $(shell $(CONTAINER) machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null)
TC_ENV    = $(if $(DOCKER_HOST),,$(if $(TC_SOCKET),DOCKER_HOST=unix://$(TC_SOCKET) TESTCONTAINERS_RYUK_DISABLED=true))

# BACKEND_ENV lets a target add environment variables (see backend-run-postgres).
BACKEND_ENV    =
BACKEND_GRADLE = cd backend && $(BACKEND_ENV) $(TC_ENV) JAVA_HOME=$(JDK21_HOME) ./gradlew --console=plain
DB_COMPOSE     := $(CONTAINER) compose -f backend/compose.yaml

.PHONY: backend-run
backend-run: ## Run the Spring Boot backend on :8081 with in-memory storage (seeded)
	$(BACKEND_GRADLE) bootRun

.PHONY: backend-run-postgres
backend-run-postgres: BACKEND_ENV = SPRING_PROFILES_ACTIVE=postgres
backend-run-postgres: db-up ## Run the backend on :8081 against the local Postgres (TODO_SEED_ENABLED=true to seed an empty DB)
	$(BACKEND_GRADLE) bootRun

.PHONY: backend-test
backend-test: ## Run backend tests: in-memory, plus Postgres via Testcontainers when a container runtime is up
	$(BACKEND_GRADLE) test

.PHONY: backend-build
backend-build: ## Build the executable jar (backend/build/libs)
	$(BACKEND_GRADLE) bootJar

.PHONY: backend-smoke
backend-smoke: ## Run the CRUD smoke test against a running backend
	@BASE_URL=$(BACKEND_URL)/api/v1 scripts/smoke.sh

.PHONY: db-up
db-up: ## Start the local PostgreSQL container on :5433
	$(DB_COMPOSE) up -d
	@printf "Waiting for PostgreSQL"; for i in $$(seq 1 30); do \
		$(CONTAINER) exec todo-db pg_isready -U todo -d todo -q >/dev/null 2>&1 && break; printf "."; sleep 1; done; echo

.PHONY: db-down
db-down: ## Stop the local PostgreSQL container (data is kept)
	$(DB_COMPOSE) down

.PHONY: db-reset
db-reset: ## Stop PostgreSQL and delete its data volume
	$(DB_COMPOSE) down -v

# --- End-to-end journey ------------------------------------------------------------------------------

# memory | postgres | mock. The journey boots the emulator if none is running.
E2E_TARGET ?= memory
# adb (no extra install) | maestro (brew install mobile-dev-inc/tap/maestro)
E2E_DRIVER ?= adb

.PHONY: e2e-android
e2e-android: ## Android journey against a real server (E2E_TARGET=memory|postgres|mock, E2E_DRIVER=adb|maestro, E2E_PUBLISH=1 refreshes docs/e2e)
	@E2E_TARGET=$(E2E_TARGET) E2E_DRIVER=$(E2E_DRIVER) E2E_PUBLISH=$(E2E_PUBLISH) JDK21_HOME=$(JDK21_HOME) CONTAINER=$(CONTAINER) \
		scripts/e2e/android-journey.sh

# --- iOS ---------------------------------------------------------------------

# Needs Xcode with the iOS platform matching its SDK installed (Xcode > Settings > Components).
# Override IOS_DEST for another simulator, e.g. IOS_DEST='platform=iOS Simulator,name=iPhone 16e'.
IOS_DEST ?= platform=iOS Simulator,name=iPhone 17
IOS_DERIVED ?= $(CURDIR)/ios/build/DerivedData
# The OpenAPI generator is a SwiftPM build-tool plugin; skip the interactive trust prompt.
XCODEBUILD := xcodebuild -destination '$(IOS_DEST)' -derivedDataPath $(IOS_DERIVED) \
	-skipPackagePluginValidation -skipMacroValidation

.PHONY: ios-build
ios-build: ## Build the iOS app for the simulator (generates the API client from the contract)
	$(XCODEBUILD) -project ios/Todo.xcodeproj -scheme Todo -configuration Debug build

.PHONY: ios-test
ios-test: ## Run iOS unit tests (view model + repository) on a simulator
	cd ios/TodoKit && $(XCODEBUILD) -scheme TodoKit test
