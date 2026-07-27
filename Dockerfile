# syntax=docker/dockerfile:1.7
#
# Pantalk Ghost - Ubuntu 24.04 + the original CBK Openbox/KasmVNC desktop.
#
# Build targets:
#   core        - shared runtime/tooling baseline (agent process support)
#   base        - core + desktop UI substrate (X11/Openbox/KasmVNC)
#   base-plus   - desktop software/tooling bundle (without runtime configs)
#   system      - config/runtime layer on top of base-plus
#   ghost       - independently runnable Pantalk Ghost image (default)
#
# Local use:
#   docker build -t pantalk/ghost:local .
#   docker run --rm -d --name pantalk-ghost --shm-size=1g \
#     -p 127.0.0.1:6902:6901 pantalk/ghost:local
#   Open http://localhost:6902
#

# ═══════════════════════════════════════════════════════════════════
# Stage: core - shared runtime/tooling baseline for agent workloads.
# ═══════════════════════════════════════════════════════════════════
FROM ubuntu:24.04 AS core

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive

RUN arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
        amd64|arm64) ;; \
        *) echo "Pantalk Ghost does not support linux/$arch" >&2; exit 1 ;; \
    esac

# Core tools and runtimes (aligned with shell rootfs capabilities).
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash coreutils curl git openssh-client jq socat wget ca-certificates sudo \
    tar zip unzip file procps openssl \
    dnsutils iproute2 haveged \
    sqlite3 \
    python3 python3-pip python-is-python3 \
    python3-numpy python3-pandas python3-scipy python3-requests \
    ipython3 \
    vim ripgrep git-lfs \
    s3fs fuse \
    && rm -rf /var/lib/apt/lists/*

# Node.js 24, matching the current agent runtime toolchain.
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/* && \
    node --version && npm --version

# Keep the package manager stable across image rebuilds.
RUN corepack enable && corepack prepare pnpm@10.13.1 --activate && \
    pnpm --version

# Mike Farah yq.
ARG YQ_VERSION=4.44.6
RUN arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${arch}" \
        -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq && \
    yq --version

# Required directories.
RUN mkdir -p /app /data /outputs /workspace /var/log/ghost

# Enable user_allow_other for FUSE mounts so s3fs uid/gid options work.
RUN echo 'user_allow_other' >> /etc/fuse.conf

# Alias ipython to ipython3 and pip to pip3 for consistency with shell.
# Note: python-is-python3 package already handles python→python3.
RUN ln -sf /usr/bin/ipython3 /usr/bin/ipython && \
    ln -sf /usr/bin/pip3 /usr/bin/pip

# Sanity check: verify python, pip, and ipython aliases work correctly.
# This ensures the aliases remain valid even if the base image changes.
RUN set -eux; \
    python --version 2>&1 | grep -i "Python 3" || { echo "ERROR: 'python' must be Python 3"; exit 1; }; \
    pip --version | grep -i "python 3" || { echo "ERROR: 'pip' must use Python 3"; exit 1; }; \
    ipython --version >/dev/null || { echo "ERROR: 'ipython' command not found"; exit 1; }; \
    echo "✓ Python aliases verified: python=$(python --version), pip=$(pip --version | cut -d' ' -f1-2), ipython=$(ipython --version)"


# ═══════════════════════════════════════════════════════════════════
# Stage: base - desktop UI substrate layered on top of core.
# ═══════════════════════════════════════════════════════════════════
FROM core AS base

USER root

# KasmVNC supplies its own X server (Xvnc), so the `xorg` metapackage is not
# installed: it would add the hardware X server, drivers, udev, and systemd.
# The generated xstartup is replaced below, making `x11-xserver-utils`
# unnecessary too. Keep KasmVNC's direct X authentication, keyboard, and core
# font dependencies explicit so a future autoremove cannot take them out.
RUN apt-get update && apt-get install -y --no-install-recommends \
    xdg-utils ssl-cert \
    xauth xkb-data x11-xkb-utils xfonts-base \
    xterm dbus-x11 x11-utils \
    scrot \
    openbox obconf tint2 kitty ranger feh picom htop xdotool wmctrl \
    fonts-noto fonts-noto-color-emoji \
    libnss3 libatk1.0-0t64 libatk-bridge2.0-0t64 libcups2t64 libdrm2 \
    libxkbcommon0 libxcomposite1 libxdamage1 libxrandr2 libgbm1 \
    libpango-1.0-0 libasound2t64 libxshmfence1 \
    && rm -rf /var/lib/apt/lists/*

# Cortile (dynamic tiling on top of Openbox).
ARG CORTILE_VERSION=2.5.2
RUN set -eux; \
        arch="$(dpkg --print-architecture)"; \
        case "$arch" in \
            amd64) cortile_arch="amd64" ;; \
            arm64) cortile_arch="arm64" ;; \
            armhf) cortile_arch="arm" ;; \
            i386) cortile_arch="386" ;; \
            *) echo "Unsupported architecture for Cortile: $arch" >&2; exit 1 ;; \
        esac; \
        tmp_dir="$(mktemp -d)"; \
        curl -fsSL "https://github.com/leukipp/cortile/releases/download/v${CORTILE_VERSION}/cortile_${CORTILE_VERSION}_linux_${cortile_arch}.tar.gz" \
            | tar -xz -C "$tmp_dir"; \
        install -m 0755 "$tmp_dir/cortile" /usr/local/bin/cortile; \
        rm -rf "$tmp_dir"; \
    cortile --help >/dev/null 2>&1 || true

# KasmVNC.
ARG KASMVNC_VERSION=1.4.0
RUN arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    curl -fsSL "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_noble_${KASMVNC_VERSION}_${arch}.deb" \
        -o /tmp/kasmvnc.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends /tmp/kasmvnc.deb && \
    rm -f /tmp/kasmvnc.deb && \
    rm -rf /var/lib/apt/lists/*

# ═══════════════════════════════════════════════════════════════════
# Stage: base-plus - desktop software/tooling bundle.
# ═══════════════════════════════════════════════════════════════════
FROM base AS base-plus

ARG TARGETARCH
ARG PANTALK_VERSION=0.0.12
ARG AGENT_BROWSER_VERSION=0.33.0
ARG GITHUB_COPILOT_VERSION=1.0.75
ARG CODEX_VERSION=0.145.0
ARG CHATBOTKIT_CLI_VERSION=1.38.0
ARG KIMI_CODE_VERSION=0.29.1
ARG CLAUDE_CODE_VERSION=2.1.220

# Docker CLI.
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor \
        -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu noble stable" \
        > /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y --no-install-recommends docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*

# Pinned coding CLIs. @moonshot-ai/kimi-code provides the `kimi` binary used
# with Pantalk's ACP driver (`command: kimi acp`).
RUN npm install -g \
    "agent-browser@${AGENT_BROWSER_VERSION}" \
    "@github/copilot@${GITHUB_COPILOT_VERSION}" \
    "@openai/codex@${CODEX_VERSION}" \
    "@chatbotkit/cli@${CHATBOTKIT_CLI_VERSION}" \
    "@moonshot-ai/kimi-code@${KIMI_CODE_VERSION}" \
    "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" && \
    agent-browser --version && \
    copilot --version && \
    cbk --version && \
    codex --version && \
    claude --version && \
    kimi --version

# Pantalk release. The archive checksum is verified against the checksums file
# published with the same GitHub release.
RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
        amd64|arm64) ;; \
        *) echo "Unsupported Pantalk architecture: $arch" >&2; exit 1 ;; \
    esac; \
    archive="pantalk-v${PANTALK_VERSION}-linux-${arch}.tar.gz"; \
    release_url="https://github.com/pantalk/pantalk/releases/download/v${PANTALK_VERSION}"; \
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

# GitHub CLI.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && apt-get install -y --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*

# Google does not publish Chrome for Linux ARM64. Keep the existing Chrome
# package on AMD64 and use Debian's signed Chromium package on ARM64, following
# the same approach as Kasm's own multi-architecture Ubuntu Chromium image.
RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    if [ "$arch" = "amd64" ]; then \
        curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
            -o /tmp/browser.deb; \
        apt-get update; \
        apt-get install -y --no-install-recommends /tmp/browser.deb; \
        rm -f /tmp/browser.deb; \
    else \
        mkdir -p /etc/apt/keyrings; \
        curl -fsSL https://ftp-master.debian.org/keys/archive-key-12.asc \
            -o /etc/apt/keyrings/debian-archive-key-12.asc; \
        printf '%s\n' \
            'deb [arch=arm64 signed-by=/etc/apt/keyrings/debian-archive-key-12.asc] https://deb.debian.org/debian bookworm main' \
            > /etc/apt/sources.list.d/debian-bookworm.list; \
        printf '%s\n' \
            'Package: *' \
            'Pin: release n=bookworm' \
            'Pin-Priority: 100' \
            > /etc/apt/preferences.d/debian-bookworm; \
        apt-get update; \
        apt-get install -y --no-install-recommends chromium; \
        rm -f \
            /etc/apt/keyrings/debian-archive-key-12.asc \
            /etc/apt/preferences.d/debian-bookworm \
            /etc/apt/sources.list.d/debian-bookworm.list; \
    fi; \
    rm -rf /var/lib/apt/lists/*

# ═══════════════════════════════════════════════════════════════════
# Stage: system - configuration/runtime layer over base-plus.
# ═══════════════════════════════════════════════════════════════════
FROM base-plus AS system

# KasmVNC UI customisation.
COPY kasm/custom.css /usr/share/kasmvnc/www/assets/custom.css
COPY kasm/favicon.svg /usr/share/kasmvnc/www/assets/favicon.svg
COPY kasm/mascot.css /usr/share/kasmvnc/www/assets/mascot.css
COPY kasm/mascot.js /usr/share/kasmvnc/www/assets/mascot.js
COPY kasm/patch.sh /tmp/kasm-patch.sh
RUN chmod +x /tmp/kasm-patch.sh && /tmp/kasm-patch.sh && rm /tmp/kasm-patch.sh

# Deterministic Pantalk-branded desktop wallpaper.
COPY wallpaper/pantalk-ghost.svg /usr/share/backgrounds/pantalk-ghost.svg

# User + access configuration belongs to runtime/config layer.
RUN if id -u ghost >/dev/null 2>&1; then \
        :; \
    elif id -u ubuntu >/dev/null 2>&1; then \
        usermod -l ghost -d /home/ghost -m ubuntu && groupmod -n ghost ubuntu; \
    else \
        groupadd --system ghost && useradd --system --create-home --home-dir /home/ghost --gid ghost --shell /bin/bash ghost; \
    fi && \
    mkdir -p \
        /home/ghost/.vnc \
        /home/ghost/.config \
        /home/ghost/.local/share/applications \
        /home/ghost/.codex \
        /home/ghost/.claude \
        /home/ghost/.kimi && \
    chown -R ghost:ghost /home/ghost

ENV HOME=/home/ghost
ENV GTK_THEME=PantalkGhost
# Chrome and Chromium ask GTK for embedded symbolic window-control resources.
# Overlay only those four resources so their custom frames use the exact
# Openbox glyph masks.
ENV G_RESOURCE_OVERLAYS=/org/gtk/libgtk=/usr/share/pantalk-ghost/gtk-overlay

# Browser popup menus come from Linux's native color pipeline rather than
# extension-theme colors. A GTK system theme therefore styles the menus,
# dialogs, toolbar, tabs, and omnibox as one coherent near-black surface.
COPY gtk/PantalkGhost /usr/share/themes/PantalkGhost
COPY gtk/generate-resource-overlay.py /tmp/generate-gtk-resource-overlay.py
COPY openbox/theme /tmp/openbox-theme
# Generate real symbolic PNGs directly from the Openbox XBM source assets.
RUN python3 /tmp/generate-gtk-resource-overlay.py \
        /tmp/openbox-theme /usr/share/pantalk-ghost/gtk-overlay && \
    rm -rf /tmp/generate-gtk-resource-overlay.py /tmp/openbox-theme

# Sudo configuration belongs to the runtime/config layer.
RUN mkdir -p /etc/sudoers.d /home/ghost && \
    echo "ghost ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ghost && \
    chmod 0440 /etc/sudoers.d/ghost && \
    touch /home/ghost/.sudo_as_admin_successful /home/ghost/.hushlogin && \
    chown ghost:ghost /home/ghost/.sudo_as_admin_successful /home/ghost/.hushlogin

# Browser preferences. `system_theme: 1` selects GTK on Linux; unlike an
# extension theme, it also reaches native menus and other popup surfaces.
RUN for config_dir in google-chrome chromium; do \
        mkdir -p "/home/ghost/.config/$config_dir/Default"; \
        printf '{\n  "browser": {\n    "has_seen_welcome_page": true,\n    "check_default_browser": false\n  },\n  "bookmark_bar": { "show_on_all_tabs": false },\n  "distribution": {\n    "skip_first_run_ui": true,\n    "show_welcome_page": false,\n    "import_bookmarks": false,\n    "make_chrome_default_for_user": false,\n    "suppress_first_run_default_browser_prompt": true\n  },\n  "extensions": {\n    "theme": {\n      "system_theme": 1\n    }\n  }\n}' \
            > "/home/ghost/.config/$config_dir/Default/Preferences"; \
        touch "/home/ghost/.config/$config_dir/First Run"; \
    done && \
    chown -R ghost:ghost \
        /home/ghost/.config/google-chrome \
        /home/ghost/.config/chromium

# Suppress the default-browser prompt via managed policy. Do not set
# BrowserThemeColor here: that policy overrides the GTK system theme.
RUN mkdir -p \
        /etc/opt/chrome/policies/managed \
        /etc/chromium/policies/managed && \
    printf '{\n  "DefaultBrowserSettingEnabled": false,\n  "BrowserSignin": 0,\n  "HomepageLocation": "file:///opt/browser/index.html",\n  "HomepageIsNewTabPage": false,\n  "ShowHomeButton": true,\n  "RestoreOnStartup": 4,\n  "RestoreOnStartupURLs": [\n    "file:///opt/browser/index.html"\n  ]\n}' \
        > /etc/opt/chrome/policies/managed/ghost-policy.json && \
    cp /etc/opt/chrome/policies/managed/ghost-policy.json \
        /etc/chromium/policies/managed/ghost-policy.json

# Register the architecture's browser as the system default.
RUN mkdir -p /home/ghost/.local/share/applications && \
    chown -R ghost:ghost /home/ghost/.local && \
    if [ -x /opt/google/chrome/google-chrome ]; then \
        browser=/opt/google/chrome/google-chrome; \
    else \
        browser=/usr/bin/chromium; \
    fi && \
    update-alternatives --install /usr/bin/x-www-browser x-www-browser "$browser" 200 2>/dev/null || true && \
    update-alternatives --set x-www-browser "$browser" 2>/dev/null || true

# @note MIME associations and xdg defaults are configured in init.sh at
# runtime so they work in both Docker local and rootfs deployments.
# The browser wrapper lives in shell/ and is copied below.
ENV BROWSER=chromium

# Openbox config - dark minimal theme with tint2 panel.
COPY openbox/rc.xml /etc/xdg/openbox/rc.xml
COPY openbox/menu.xml /etc/xdg/openbox/menu.xml
COPY openbox/autostart /etc/xdg/openbox/autostart
COPY cortile/cortilectl /usr/local/bin/cortilectl
COPY shell/welcome /usr/local/bin/welcome
COPY shell/chromium /usr/local/bin/chromium
COPY shell/agent-runtime-login /usr/local/bin/agent-runtime-login
COPY shell/ghost-panel-status /usr/local/bin/ghost-panel-status
COPY shell/ghost-harness /usr/local/bin/ghost-harness
RUN mkdir -p /etc/bash.bashrc.d
COPY shell/bashrc /etc/bash.bashrc.d/pantalk-prompt.sh
RUN echo '[ -d /etc/bash.bashrc.d ] && for f in /etc/bash.bashrc.d/*.sh; do . "$f"; done' >> /etc/bash.bashrc
COPY browser /opt/browser
COPY config/pantalk.yaml /usr/local/share/ghost/pantalk-config.yaml
COPY --chown=ghost:ghost workspace /usr/local/share/ghost/workspace
COPY openbox/theme /usr/share/themes/Triste-Crimson/openbox-3
COPY tint2/tint2rc /etc/xdg/tint2/tint2rc
RUN chmod +x \
    /etc/xdg/openbox/autostart \
    /usr/local/bin/cortilectl \
    /usr/local/bin/welcome \
    /usr/local/bin/chromium \
    /usr/local/bin/agent-runtime-login \
    /usr/local/bin/ghost-panel-status \
    /usr/local/bin/ghost-harness

# Ensure a desktop entry exists for openbox-session so KasmVNC's
# select-de mechanism can discover and start it.
RUN mkdir -p /usr/share/xsessions && \
    printf '[Desktop Entry]\nName=Openbox\nExec=openbox-session\nType=Application\n' \
    > /usr/share/xsessions/openbox.desktop

# KasmVNC configuration.
USER ghost

# Default Cortile config: floating by default, user enables tiling on demand.
RUN mkdir -p "$HOME/.config/cortile"
COPY --chown=ghost:ghost cortile/cortile-config.toml /home/ghost/.config/cortile/config.toml

# xstartup - launch Openbox.
RUN printf '#!/bin/bash\nexec openbox-session\n' > "$HOME/.vnc/xstartup" && \
    chmod +x "$HOME/.vnc/xstartup" && \
    touch "$HOME/.vnc/.de-was-selected"

# Disable SSL, set websocket port.
RUN printf 'network:\n  ssl:\n    pem_certificate:\n    pem_key:\n    require_ssl: false\n  websocket_port: 6901\n  udp:\n    public_ip: auto\n' \
    > "$HOME/.vnc/kasmvnc.yaml"

# Self-signed cert (kasmvncserver wrapper still checks for it).
RUN openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout "$HOME/.vnc/self.pem" -out "$HOME/.vnc/self.pem" \
    -subj "/CN=ghost" 2>/dev/null

# VNC password.
RUN bash -c 'echo -e "kasmvnc\nkasmvnc\n" | kasmvncpasswd -u ghost -wo'

EXPOSE 6901
WORKDIR /workspace
VOLUME ["/workspace", "/home/ghost/.config/pantalk", "/home/ghost/.local/share/pantalk", "/home/ghost/.codex", "/home/ghost/.claude", "/home/ghost/.kimi"]


# ═══════════════════════════════════════════════════════════════════
# Target: ghost - independently runnable Pantalk environment.
# ═══════════════════════════════════════════════════════════════════
FROM system AS ghost

USER root

COPY init.sh /init
RUN chmod +x /init

HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=5 \
    CMD curl -fsS http://127.0.0.1:6901/ >/dev/null || exit 1
ENTRYPOINT ["/init"]
