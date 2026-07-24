SHELL := /bin/bash
.DEFAULT_GOAL := help

DOCKER ?= docker
IMAGE ?= pantalk/station:local
CONTAINER ?= pantalk-station
PLATFORM ?= linux/amd64
PANTALK_VERSION ?= 0.0.10
BIND_ADDRESS ?= 127.0.0.1
PORT ?= 6902
RESOLUTION ?= 1920x1080
PANTALK_AUTOSTART ?= true
VNC_STATS ?= false
VOLUME_PREFIX ?= pantalk-station

# Pass a GPU through when the host has one. Empty on hosts without /dev/dri,
# such as Podman and Docker VMs on macOS and Windows.
GPU_DEVICE := $(shell test -d /dev/dri && echo --device=/dev/dri)

.PHONY: help build run recreate up test smoke stop logs vnc-log status url

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
	@echo "  make vnc-log    Follow the KasmVNC session log (encoder statistics)"
	@echo "  make status     Show container and health status"
	@echo "  make stop       Stop and remove the container"
	@echo "  make url        Print the local browser URL"
	@echo
	@echo "Overrides: PORT=8080 RESOLUTION=1600x900 PANTALK_VERSION=0.0.10"
	@echo "           PANTALK_AUTOSTART=false"
	@echo "           VNC_STATS=true  (log KasmVNC encoder statistics)"

build:
	$(DOCKER) build \
		--platform "$(PLATFORM)" \
		--build-arg TARGETARCH=amd64 \
		--build-arg "PANTALK_VERSION=$(PANTALK_VERSION)" \
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
			$(GPU_DEVICE) \
			--publish "$(BIND_ADDRESS):$(PORT):6901" \
			--env "STATION_RESOLUTION=$(RESOLUTION)" \
			--env "PANTALK_AUTOSTART=$(PANTALK_AUTOSTART)" \
			--env "STATION_VNC_STATS=$(VNC_STATS)" \
			--volume "$(VOLUME_PREFIX)-workspace:/workspace" \
			--volume "$(VOLUME_PREFIX)-config:/home/agent/.config/pantalk" \
			--volume "$(VOLUME_PREFIX)-state:/home/agent/.local/share/pantalk" \
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
	@ready=false; \
	for attempt in $$(seq 1 30); do \
		if curl --fail --silent "http://$(BIND_ADDRESS):$(PORT)/index.html" >/dev/null; then \
			ready=true; \
			break; \
		fi; \
		sleep 2; \
	done; \
	if [ "$$ready" != "true" ]; then \
		echo "Pantalk Station did not become ready within 60 seconds."; \
		$(DOCKER) logs --tail 50 "$(CONTAINER)" || true; \
		exit 1; \
	fi; \
	if $(DOCKER) exec "$(CONTAINER)" sh -c \
		'command -v ergo || command -v halloy || command -v halloy-station' \
		>/dev/null 2>&1; then \
		echo "Station still contains bundled IRC software."; \
		exit 1; \
	fi; \
	echo "Pantalk Station is ready and transport-neutral: http://$(BIND_ADDRESS):$(PORT)"

stop:
	@if $(DOCKER) container inspect "$(CONTAINER)" >/dev/null 2>&1; then \
		$(DOCKER) rm --force "$(CONTAINER)"; \
	else \
		echo "Container $(CONTAINER) does not exist."; \
	fi

logs:
	$(DOCKER) logs --follow "$(CONTAINER)"

# KasmVNC writes Xvnc's output to a per-session log rather than to the
# container log, so the VNC_STATS encoder statistics only show up here.
vnc-log:
	$(DOCKER) exec "$(CONTAINER)" \
		bash -c 'tail --lines=200 --follow /home/agent/.vnc/*:1.log'

status:
	@$(DOCKER) ps --all \
		--filter "name=^/$(CONTAINER)$$" \
		--format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

url:
	@echo "Open http://$(BIND_ADDRESS):$(PORT)"
