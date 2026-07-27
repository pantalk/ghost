SHELL := /bin/bash
.DEFAULT_GOAL := help

DOCKER ?= docker
IMAGE ?= pantalk/ghost:local
CONTAINER ?= pantalk-ghost
NATIVE_ARCH := $(shell uname -m | sed \
	-e 's/^x86_64$$/amd64/' \
	-e 's/^aarch64$$/arm64/')
PLATFORM ?= linux/$(NATIVE_ARCH)
TARGETARCH ?= $(word 2,$(subst /, ,$(PLATFORM)))
PANTALK_VERSION ?= 0.0.12
AGENT_BROWSER_VERSION ?= 0.33.0
GITHUB_COPILOT_VERSION ?= 1.0.75
CODEX_VERSION ?= 0.145.0
CHATBOTKIT_CLI_VERSION ?= 1.38.0
KIMI_CODE_VERSION ?= 0.29.1
CLAUDE_CODE_VERSION ?= 2.1.220
BIND_ADDRESS ?= 127.0.0.1
PORT ?= 6902
RESOLUTION ?= 1920x1080
PANTALK_AUTOSTART ?= true
VNC_STATS ?= false
VOLUME_PREFIX ?= pantalk-ghost

# Pass render nodes only. `--device=/dev/dri` would also hand over card*, the
# DRM master/modesetting node, which nothing in this container uses.
GPU_DEVICE := $(shell for node in /dev/dri/renderD*; do \
	[ -e "$$node" ] && echo "--device=$$node"; done)

.PHONY: help check build run recreate up test smoke stop logs vnc-log status url size-report

help:
	@echo "Pantalk Ghost local Docker workflow"
	@echo
	@echo "  make check      Validate scripts, tests, and pinned metadata"
	@echo "  make build      Build $(IMAGE)"
	@echo "  make run        Start or create the Ghost container"
	@echo "  make recreate   Recreate the container without rebuilding"
	@echo "  make up         Build and recreate the container"
	@echo "  make test       Build, run, and smoke-test the browser endpoint"
	@echo "  make smoke      Test the running browser endpoint"
	@echo "  make logs       Follow container logs"
	@echo "  make vnc-log    Follow the KasmVNC session log (encoder statistics)"
	@echo "  make status     Show container and health status"
	@echo "  make stop       Stop and remove the container"
	@echo "  make url        Print the local browser URL"
	@echo "  make size-report  Report the graphical stack's share of the image"
	@echo
	@echo "Overrides: PORT=8080 RESOLUTION=1600x900 PANTALK_VERSION=0.0.12"
	@echo "           PLATFORM=linux/arm64 (default: $(PLATFORM))"
	@echo "           PANTALK_AUTOSTART=false"
	@echo "           VNC_STATS=true  (log KasmVNC encoder statistics)"

check:
	bash -n init.sh openbox/autostart kasm/patch.sh \
		shell/agent-runtime-login \
		shell/ghost-panel-status shell/ghost-harness \
		shell/chromium shell/welcome \
		tests/test-agent-runtime-login.sh tests/test-ghost.sh \
		tests/smoke-container.sh \
		tools/size-report.sh
	bash tests/test-agent-runtime-login.sh
	bash tests/test-ghost.sh
	@grep -q "^ARG PANTALK_VERSION=$(PANTALK_VERSION)$$" Dockerfile
	@grep -q "^ARG AGENT_BROWSER_VERSION=$(AGENT_BROWSER_VERSION)$$" Dockerfile
	@grep -q "^ARG GITHUB_COPILOT_VERSION=$(GITHUB_COPILOT_VERSION)$$" Dockerfile
	@grep -q "^ARG CODEX_VERSION=$(CODEX_VERSION)$$" Dockerfile
	@grep -q "^ARG CHATBOTKIT_CLI_VERSION=$(CHATBOTKIT_CLI_VERSION)$$" Dockerfile
	@grep -q "^ARG KIMI_CODE_VERSION=$(KIMI_CODE_VERSION)$$" Dockerfile
	@grep -q "^ARG CLAUDE_CODE_VERSION=$(CLAUDE_CODE_VERSION)$$" Dockerfile
	@echo "Ghost metadata, runtime login helper, and shell syntax are valid."

build:
	$(DOCKER) build \
		--platform "$(PLATFORM)" \
		--build-arg "TARGETARCH=$(TARGETARCH)" \
		--build-arg "PANTALK_VERSION=$(PANTALK_VERSION)" \
		--build-arg "AGENT_BROWSER_VERSION=$(AGENT_BROWSER_VERSION)" \
		--build-arg "GITHUB_COPILOT_VERSION=$(GITHUB_COPILOT_VERSION)" \
		--build-arg "CODEX_VERSION=$(CODEX_VERSION)" \
		--build-arg "CHATBOTKIT_CLI_VERSION=$(CHATBOTKIT_CLI_VERSION)" \
		--build-arg "KIMI_CODE_VERSION=$(KIMI_CODE_VERSION)" \
		--build-arg "CLAUDE_CODE_VERSION=$(CLAUDE_CODE_VERSION)" \
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
			--env "GHOST_RESOLUTION=$(RESOLUTION)" \
			--env "PANTALK_AUTOSTART=$(PANTALK_AUTOSTART)" \
			--env "GHOST_VNC_STATS=$(VNC_STATS)" \
			--volume "$(VOLUME_PREFIX)-workspace:/workspace" \
			--volume "$(VOLUME_PREFIX)-config:/home/ghost/.config/pantalk" \
			--volume "$(VOLUME_PREFIX)-state:/home/ghost/.local/share/pantalk" \
			--volume "$(VOLUME_PREFIX)-codex:/home/ghost/.codex" \
			--volume "$(VOLUME_PREFIX)-claude:/home/ghost/.claude" \
			--volume "$(VOLUME_PREFIX)-kimi:/home/ghost/.kimi" \
			"$(IMAGE)"; \
	fi
	@$(MAKE) --no-print-directory url

recreate:
	@$(MAKE) --no-print-directory stop
	@$(MAKE) --no-print-directory run

up: build recreate

test: check up smoke

smoke:
	@echo "Waiting for Ghost at http://$(BIND_ADDRESS):$(PORT) ..."
	@ready=false; \
	for attempt in $$(seq 1 30); do \
		if curl --fail --silent "http://$(BIND_ADDRESS):$(PORT)/index.html" >/dev/null; then \
			ready=true; \
			break; \
		fi; \
		sleep 2; \
	done; \
	if [ "$$ready" != "true" ]; then \
		echo "Pantalk Ghost did not become ready within 60 seconds."; \
		$(DOCKER) logs --tail 50 "$(CONTAINER)" || true; \
		exit 1; \
	fi; \
	DOCKER="$(DOCKER)" bash tests/smoke-container.sh \
		"$(CONTAINER)" "$(TARGETARCH)"; \
	echo "Pantalk Ghost is ready and transport-neutral: http://$(BIND_ADDRESS):$(PORT)"

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
		bash -c 'tail --lines=200 --follow /home/ghost/.vnc/*:1.log'

status:
	@$(DOCKER) ps --all \
		--filter "name=^/$(CONTAINER)$$" \
		--format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

url:
	@echo "Open http://$(BIND_ADDRESS):$(PORT)"

size-report:
	@DOCKER="$(DOCKER)" bash tools/size-report.sh "$(IMAGE)"
