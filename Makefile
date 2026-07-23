SHELL := /bin/bash
.DEFAULT_GOAL := help

DOCKER ?= docker
IMAGE ?= pantalk/station:local
CONTAINER ?= pantalk-station
PLATFORM ?= linux/amd64
PANTALK_VERSION ?= 0.0.7
HALLOY_VERSION ?= 2026.7.2
ERGO_VERSION ?= 2.19.0
BIND_ADDRESS ?= 127.0.0.1
PORT ?= 6902
RESOLUTION ?= 1920x1080
PANTALK_AUTOSTART ?= true
IRC_AUTOSTART ?= true
VOLUME_PREFIX ?= pantalk-station

.PHONY: help build run recreate up test smoke stop logs status url

help:
	@echo "Pantalk Station local Docker workflow"
	@echo
	@echo "  make build      Build $(IMAGE)"
	@echo "  make run        Start or create the Station container"
	@echo "  make recreate   Recreate the container without rebuilding"
	@echo "  make up         Build and recreate the container"
	@echo "  make test       Build, run, and smoke-test the browser endpoint"
	@echo "  make smoke      Test the running browser endpoint"
	@echo "  make logs       Follow container logs"
	@echo "  make status     Show container and health status"
	@echo "  make stop       Stop and remove the container"
	@echo "  make url        Print the local browser URL"
	@echo
	@echo "Overrides: PORT=8080 RESOLUTION=1600x900 PANTALK_VERSION=0.0.7"
	@echo "           IRC_AUTOSTART=false PANTALK_AUTOSTART=false"

build:
	$(DOCKER) build \
		--platform "$(PLATFORM)" \
		--build-arg TARGETARCH=amd64 \
		--build-arg "PANTALK_VERSION=$(PANTALK_VERSION)" \
		--build-arg "HALLOY_VERSION=$(HALLOY_VERSION)" \
		--build-arg "ERGO_VERSION=$(ERGO_VERSION)" \
		--tag "$(IMAGE)" \
		.

run:
	@if $(DOCKER) container inspect "$(CONTAINER)" >/dev/null 2>&1; then \
		if [ "$$($(DOCKER) container inspect --format '{{.State.Running}}' "$(CONTAINER)")" = "true" ]; then \
			echo "Container $(CONTAINER) is already running."; \
		else \
			$(DOCKER) start "$(CONTAINER)"; \
		fi; \
	else \
		$(DOCKER) run --detach \
			--name "$(CONTAINER)" \
			--platform "$(PLATFORM)" \
			--restart unless-stopped \
			--shm-size 1g \
			--publish "$(BIND_ADDRESS):$(PORT):6901" \
			--env "STATION_RESOLUTION=$(RESOLUTION)" \
			--env "PANTALK_AUTOSTART=$(PANTALK_AUTOSTART)" \
			--env "STATION_IRC_AUTOSTART=$(IRC_AUTOSTART)" \
			--volume "$(VOLUME_PREFIX)-workspace:/workspace" \
			--volume "$(VOLUME_PREFIX)-config:/home/agent/.config/pantalk" \
			--volume "$(VOLUME_PREFIX)-halloy:/home/agent/.config/halloy" \
			--volume "$(VOLUME_PREFIX)-halloy-state:/home/agent/.local/share/halloy" \
			--volume "$(VOLUME_PREFIX)-state:/home/agent/.local/share/pantalk" \
			--volume "$(VOLUME_PREFIX)-irc:/home/agent/.local/share/ergo" \
			--volume "$(VOLUME_PREFIX)-codex:/home/agent/.codex" \
			--volume "$(VOLUME_PREFIX)-claude:/home/agent/.claude" \
			"$(IMAGE)"; \
	fi
	@$(MAKE) --no-print-directory url

recreate:
	@$(MAKE) --no-print-directory stop
	@$(MAKE) --no-print-directory run

up: build recreate

test: up smoke

smoke:
	@echo "Waiting for Station at http://$(BIND_ADDRESS):$(PORT) ..."
	@for attempt in $$(seq 1 30); do \
		if curl --fail --silent "http://$(BIND_ADDRESS):$(PORT)/index.html" >/dev/null; then \
			echo "Pantalk Station is ready: http://$(BIND_ADDRESS):$(PORT)"; \
			exit 0; \
		fi; \
		sleep 2; \
	done; \
	echo "Pantalk Station did not become ready within 60 seconds."; \
	$(DOCKER) logs --tail 50 "$(CONTAINER)" || true; \
	exit 1

stop:
	@if $(DOCKER) container inspect "$(CONTAINER)" >/dev/null 2>&1; then \
		$(DOCKER) rm --force "$(CONTAINER)"; \
	else \
		echo "Container $(CONTAINER) does not exist."; \
	fi

logs:
	$(DOCKER) logs --follow "$(CONTAINER)"

status:
	@$(DOCKER) ps --all \
		--filter "name=^/$(CONTAINER)$$" \
		--format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

url:
	@echo "Open http://$(BIND_ADDRESS):$(PORT)"
