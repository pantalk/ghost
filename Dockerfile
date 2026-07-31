# syntax=docker/dockerfile:1.7
#
# Pantalk Ghost - Pantalk and its agent runtimes on a browser-accessible
# desktop.
#
# The Openbox/KasmVNC desktop here was the original: the Launcher desktop base
# was ported from it. That base is now the shared substrate for several
# desktops, so Ghost consumes it rather than keeping a second copy of a stack it
# no longer owns alone. What remains here is Pantalk.
#
# Everything visual comes from the base. This image adds Pantalk and its
# runtimes, then installs its branding through overlay/, which is copied over
# the base's defaults.
#
# Local use:
#   docker build -t pantalk/ghost:local .
#   docker run --rm -d --name pantalk-ghost --shm-size=1g \
#     -p 127.0.0.1:6901:6901 -p 127.0.0.1:6902:6902 \
#     pantalk/ghost:local
#   Open http://localhost:6901

ARG DESKTOP_IMAGE=ghcr.io/pdparchitect/launcher-image-base-desktop:0.1.8
FROM ${DESKTOP_IMAGE}

USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG TARGETARCH

# The Python data stack the agent runtimes are expected to have on hand, plus
# s3fs for mounting object storage into the workspace. The desktop base carries
# plain python3; these are the libraries and tools on top of it.
#
# user_allow_other lets s3fs pass uid/gid options, which is what makes a bucket
# usable by the desktop account rather than only by root.
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-numpy python3-pandas python3-scipy python3-requests ipython3 \
    s3fs fuse \
    && rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/bin/ipython3 /usr/bin/ipython && \
    echo 'user_allow_other' >> /etc/fuse.conf

# Docker and GitHub CLIs remain available for agent workflows. Ghost does not
# require a host Docker socket.
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor \
        -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu noble stable" \
        > /etc/apt/sources.list.d/docker.list && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends docker-ce-cli gh && \
    rm -rf /var/lib/apt/lists/*

# Pinned coding CLIs. @moonshot-ai/kimi-code provides the `kimi` binary used
# with Pantalk's ACP driver (`command: kimi acp`). Node and npm come from the
# runtime layer in the base chain.
#
# npm's cache follows HOME, which the desktop base points at the session user's
# home. Without an explicit cache directory this root-run install leaves
# /home/agent/.npm owned by root, and then kitty cannot start and the session
# opens with no terminal at all.
ARG AGENT_BROWSER_VERSION=0.33.0
ARG GITHUB_COPILOT_VERSION=1.0.75
ARG CODEX_VERSION=0.145.0
ARG CHATBOTKIT_CLI_VERSION=1.38.0
ARG KIMI_CODE_VERSION=0.29.1
ARG CLAUDE_CODE_VERSION=2.1.220
ENV npm_config_cache=/tmp/npm-cache
RUN npm install -g \
        "agent-browser@${AGENT_BROWSER_VERSION}" \
        "@github/copilot@${GITHUB_COPILOT_VERSION}" \
        "@openai/codex@${CODEX_VERSION}" \
        "@chatbotkit/cli@${CHATBOTKIT_CLI_VERSION}" \
        "@moonshot-ai/kimi-code@${KIMI_CODE_VERSION}" \
        "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" && \
    rm -rf /tmp/npm-cache && \
    agent-browser --version && \
    copilot --version && \
    cbk --version && \
    codex --version && \
    claude --version && \
    kimi --version

# Pantalk release. The archive checksum is verified against the checksums file
# published with the same GitHub release.
ARG PANTALK_VERSION=0.0.12
ARG PANTALK_SOURCE_URL=https://github.com/pantalk/pantalk
RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
        amd64|arm64) ;; \
        *) echo "Unsupported Pantalk architecture: $arch" >&2; exit 1 ;; \
    esac; \
    archive="pantalk-v${PANTALK_VERSION}-linux-${arch}.tar.gz"; \
    release_url="${PANTALK_SOURCE_URL}/releases/download/v${PANTALK_VERSION}"; \
    curl -fsSL "${release_url}/${archive}" -o "/tmp/${archive}"; \
    curl -fsSL "${release_url}/checksums.txt" -o /tmp/pantalk-checksums.txt; \
    (cd /tmp && grep " ${archive}$" pantalk-checksums.txt | sha256sum -c -); \
    mkdir -p /tmp/pantalk-release; \
    tar -xzf "/tmp/${archive}" -C /tmp/pantalk-release --strip-components=1; \
    install -m 0755 /tmp/pantalk-release/pantalk /usr/local/bin/pantalk; \
    install -m 0755 /tmp/pantalk-release/pantalkd /usr/local/bin/pantalkd; \
    rm -rf "/tmp/${archive}" /tmp/pantalk-checksums.txt /tmp/pantalk-release; \
    pantalk version; \
    pantalkd --version

# Pantalk keeps its config and runtime state here, and both are volumes, so a
# rebuilt image resumes configured. Creating them now means the entrypoint's
# ownership pass has something to normalise on a brand-new volume.
RUN mkdir -p \
        /home/agent/.config/pantalk \
        /home/agent/.local/share/pantalk \
        /home/agent/.codex \
        /home/agent/.claude \
        /home/agent/.kimi && \
    rm -rf /home/agent/.cache /home/agent/.npm && \
    chown -R agent:agent /home/agent

# Product branding, the Pantalk starter config, and the workspace seed.
# Everything under overlay/ is installed over the base's defaults, so a file
# here wins without the base knowing this product exists.
#
# The workspace seed lands in the path the base entrypoint copies into
# /workspace on first boot, so AGENT.md reaches new and upgraded volumes alike.
COPY overlay /
RUN chmod 0755 \
        /etc/desktop/startup.d/05-agent-runtime-trust \
        /etc/desktop/startup.d/10-pantalk \
        /usr/local/bin/agent-runtime-login \
        /usr/local/bin/desktop-harness \
        /usr/local/bin/desktop-panel-status \
        /usr/local/bin/desktop-welcome \
        /usr/local/bin/kasm-mascot \
        /usr/local/bin/pantalk-greeting

# Rebrand the KasmVNC client, then add the mascot. The base already patched the
# client, so kasm-patch replaces the brand rather than injecting the asset links
# a second time; kasm-mascot runs after it because both rewrite the same <head>.
RUN kasm-patch "Pantalk Ghost" && kasm-mascot

ENV DESKTOP_TITLE="Pantalk Ghost" \
    DESKTOP_PERSISTENT_PATHS="/home/agent/.config/pantalk /home/agent/.local/share/pantalk /home/agent/.codex /home/agent/.claude /home/agent/.kimi" \
    PANTALK_CONFIG=/home/agent/.config/pantalk/config.yaml

LABEL org.opencontainers.image.title="Pantalk Ghost" \
    org.opencontainers.image.description="Pantalk and its agent runtimes in a browser-accessible desktop" \
    org.opencontainers.image.source="https://github.com/pantalk/ghost" \
    dev.pdparchitect.launcher.upstream.source="${PANTALK_SOURCE_URL}" \
    dev.pdparchitect.launcher.upstream.version="${PANTALK_VERSION}"

WORKDIR /workspace
VOLUME ["/workspace", "/home/agent/.config/pantalk", "/home/agent/.local/share/pantalk", "/home/agent/.codex", "/home/agent/.claude", "/home/agent/.kimi"]
