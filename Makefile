.DEFAULT_GOAL := help
SHELL := /bin/bash

COMPOSE := docker compose -f infrastructure/docker/docker-compose.yml -f infrastructure/docker/docker-compose.dev.yml --env-file infrastructure/docker/.env

help: ## Show this help
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install: ## Bootstrap local development
	@command -v docker >/dev/null || { echo "Install Docker first"; exit 1; }
	@test -f infrastructure/docker/.env || cp infrastructure/docker/.env.example infrastructure/docker/.env
	@echo "→ wrote infrastructure/docker/.env (edit it if you like)"
	cd services/api && python3.12 -m venv .venv && . .venv/bin/activate && pip install -e ".[dev]"
	@echo "→ done. Run: make dev"

dev: ## Run full stack locally with hot reload
	$(COMPOSE) up --build

dev-api: ## Run just the API in foreground
	cd services/api && . .venv/bin/activate && uvicorn app.main:app --reload --port 8000

dev-worker: ## Run just the worker
	cd services/worker && . .venv/bin/activate && celery -A app.main:celery worker --loglevel=DEBUG -Q default,sync,retention --concurrency=2

migrate: ## Apply DB migrations
	cd services/api && . .venv/bin/activate && alembic upgrade head

migration: ## Create a new migration with $msg (e.g. make migration msg="add foo")
	cd services/api && . .venv/bin/activate && alembic revision --autogenerate -m "$(msg)"

seed: ## Seed sample data
	cd services/api && . .venv/bin/activate && python ../../scripts/seed.py

test: test-backend test-android ## Run all tests
test-backend:
	cd services/api && . .venv/bin/activate && pytest --cov=app --cov-report=term-missing
test-android:
	cd apps/android && ./gradlew :app:testDebugUnitTest --no-daemon
test-ios:
	cd apps/ios && xcodebuild -project GalaxyHealthBridge.xcodeproj -scheme GalaxyHealthBridge -destination 'platform=iOS Simulator,name=iPhone 15' test

lint: ## Lint everything
	cd services/api && . .venv/bin/activate && ruff check . && mypy app
	cd apps/android && ./gradlew lintDebug --no-daemon
	npx -y @redocly/cli@1.25.5 lint packages/openapi/openapi.yaml

fix: ## Auto-fix lint where possible
	cd services/api && . .venv/bin/activate && ruff check . --fix && ruff format .

build: ## Build production Docker images
	$(COMPOSE) build api worker

down: ## Stop the stack
	$(COMPOSE) down

reset: ## Wipe the local stack and volumes
	$(COMPOSE) down -v

logs: ## Tail logs
	$(COMPOSE) logs -f

shell-db: ## psql into the dev DB
	$(COMPOSE) exec postgres psql -U ghb -d ghb

shell-api: ## bash into the API container
	$(COMPOSE) exec api bash

e2e: ## End-to-end tests
	bash tests/e2e/run.sh

clean: ## Remove build caches
	find . -type d -name __pycache__ -prune -exec rm -rf {} +
	rm -rf services/api/.venv services/worker/.venv .ruff_cache .mypy_cache .pytest_cache
