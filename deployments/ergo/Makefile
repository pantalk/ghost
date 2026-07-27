SHELL := /bin/bash
.DEFAULT_GOAL := help

DOCKER ?= docker
COMPOSE := $(DOCKER) compose
BASE := $(COMPOSE) --env-file .env -f compose.yaml
DEV := $(BASE) -f compose.dev.yaml

.PHONY: help prepare up dev validate smoke test logs status down urls

help:
	@echo "Pantalk Ghost with Ergo"
	@echo
	@echo "  make up        Start with the published Ghost image"
	@echo "  make dev       Build Ghost locally, then start everything"
	@echo "  make validate  Validate scripts and Compose configuration"
	@echo "  make smoke     Test the running deployment"
	@echo "  make test      Start the local build and run the smoke test"
	@echo "  make logs      Follow all deployment logs"
	@echo "  make status    Show deployment status"
	@echo "  make urls      Show the browser and IRC endpoints"
	@echo "  make down      Stop containers and preserve all data"

prepare:
	@./scripts/prepare.sh

up: prepare
	$(BASE) up --detach ergo thelounge
	$(BASE) --profile ghost up --detach ghost
	@$(MAKE) --no-print-directory urls

dev: prepare
	$(BASE) up --detach ergo thelounge
	$(DEV) --profile ghost up --detach --build ghost
	@$(MAKE) --no-print-directory urls

validate: prepare
	@bash -n scripts/prepare.sh scripts/smoke.sh
	@$(BASE) config --quiet
	@$(DEV) config --quiet
	@! grep -Fq '__IRC_CHANNEL__' .state/pantalk/config.yaml
	@$(MAKE) --no-print-directory urls >/dev/null
	@echo "Ergo deployment configuration is valid"

smoke:
	@./scripts/smoke.sh

test: dev smoke

logs:
	$(BASE) --profile ghost logs --follow

status:
	$(BASE) --profile ghost ps

down:
	$(BASE) --profile ghost down

urls:
	@test -s .env || { echo "Missing .env. Run make prepare first." >&2; exit 1; }
	@printf "IRC web client: http://%s:%s\nIRC server:     irc://%s:%s\nNode:           http://%s:%s\n" \
		"$$(sed -n 's/^THELOUNGE_BIND_ADDRESS=//p' .env)" \
		"$$(sed -n 's/^THELOUNGE_PORT=//p' .env)" \
		"$$(sed -n 's/^ERGO_BIND_ADDRESS=//p' .env)" \
		"$$(sed -n 's/^ERGO_PORT=//p' .env)" \
		"$$(sed -n 's/^GHOST_BIND_ADDRESS=//p' .env)" \
		"$$(sed -n 's/^GHOST_PORT=//p' .env)"
