SHELL := /bin/bash
.DEFAULT_GOAL := help

DOCKER ?= docker
COMPOSE := $(DOCKER) compose
BASE := $(COMPOSE) --env-file .env -f compose.yaml
DEV := $(BASE) -f compose.dev.yaml

.PHONY: help prepare up dev provision validate smoke test logs status down credentials

help:
	@echo "Pantalk Ghost with Mattermost"
	@echo
	@echo "  make up           Start with the published Ghost image"
	@echo "  make dev          Build Ghost locally, then start everything"
	@echo "  make provision    Re-run idempotent Mattermost provisioning"
	@echo "  make validate     Validate scripts and Compose configuration"
	@echo "  make smoke        Test the running deployment"
	@echo "  make test         Start the local build and run the smoke test"
	@echo "  make logs         Follow all deployment logs"
	@echo "  make status       Show deployment status"
	@echo "  make credentials  Show the initial Mattermost login"
	@echo "  make down         Stop containers and preserve all data"

prepare:
	@./scripts/prepare.sh

up: prepare
	$(BASE) up --detach postgres mattermost
	@./scripts/provision.sh
	$(BASE) --profile ghost up --detach ghost
	@echo "Mattermost: $$(awk -F= '/^MATTERMOST_SITE_URL=/{print $$2}' .env)"
	@echo "Ghost:       http://127.0.0.1:$$(awk -F= '/^GHOST_PORT=/{print $$2}' .env)"

dev: prepare
	$(BASE) up --detach postgres mattermost
	@./scripts/provision.sh
	$(DEV) --profile ghost up --detach --build ghost
	@echo "Mattermost: $$(awk -F= '/^MATTERMOST_SITE_URL=/{print $$2}' .env)"
	@echo "Ghost:       http://127.0.0.1:$$(awk -F= '/^GHOST_PORT=/{print $$2}' .env)"

provision: prepare
	$(BASE) up --detach postgres mattermost
	@./scripts/provision.sh

validate: prepare
	@bash -n scripts/prepare.sh scripts/provision.sh scripts/smoke.sh
	@$(BASE) config --quiet
	@$(DEV) config --quiet
	@$(MAKE) --no-print-directory credentials >/dev/null
	@echo "Mattermost deployment configuration is valid"

smoke:
	@./scripts/smoke.sh

test: dev smoke

logs:
	$(BASE) --profile ghost logs --follow

status:
	$(BASE) --profile ghost ps

down:
	$(BASE) --profile ghost down

credentials:
	@test -s .env || { echo "Missing .env. Run make prepare first." >&2; exit 1; }
	@printf "Mattermost: %s\nUsername:   %s\nPassword:   %s\n" \
		"$$(sed -n 's/^MATTERMOST_SITE_URL=//p' .env)" \
		"$$(sed -n 's/^MATTERMOST_ADMIN_USERNAME=//p' .env)" \
		"$$(sed -n 's/^MATTERMOST_ADMIN_PASSWORD=//p' .env)"
