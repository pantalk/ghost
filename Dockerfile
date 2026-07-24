# Pantalk Station - Ubuntu 24.04 + the original CBK Openbox/KasmVNC desktop.
#
# Build targets:
#   core        - shared runtime/tooling baseline (agent process support)
#   base        - core + desktop UI substrate (X11/Openbox/KasmVNC)
#   base-plus   - desktop software/tooling bundle (without runtime configs)
#   system      - config/runtime layer on top of base-plus
#   station     - independently runnable Pantalk Station image (default)
#
# Local use:
#   docker build -t pantalk/station:local .
#   docker run --rm -d --name pantalk-station --shm-size=1g \
#     -p 127.0.0.1:6902:6901 pantalk/station:local
#   Open http://localhost:6902
#

# ═══════════════════════════════════════════════════════════════════
# Stage: core - shared runtime/tooling baseline for agent workloads.
# ═══════════════════════════════════════════════════════════════════
FROM ubuntu:24.04 AS core

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

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

# Node.js 22 LTS (from NodeSource).
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/* && \
    node --version && npm --version

# pnpm.
RUN corepack enable && corepack prepare pnpm@latest --activate && \
    pnpm --version

# Mike Farah yq.
ARG YQ_VERSION=4.44.6
RUN curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" \
        -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq && \
    yq --version

# Required directories.
RUN mkdir -p /app /data /outputs /workspace /var/log/station

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

# X11 / display + Openbox desktop stack + fonts + Chrome deps.
RUN apt-get update && apt-get install -y --no-install-recommends \
    xdg-utils \
    ssl-cert \
    xorg xterm dbus-x11 x11-xserver-utils x11-utils \
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
RUN curl -fsSL "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_noble_${KASMVNC_VERSION}_amd64.deb" \
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
ARG PANTALK_VERSION=0.0.8

# Docker CLI.
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor \
        -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu noble stable" \
        > /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y --no-install-recommends docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*

# Global npm packages.
RUN npm install -g agent-browser @github/copilot @openai/codex @chatbotkit/cli

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

# Claude CLI.
# Install as root then move binary to a global path so all users can access it.
RUN curl -fsSL https://claude.ai/install.sh | bash && \
    if [ -f /root/.claude/local/claude ]; then \
        cp /root/.claude/local/claude /usr/local/bin/claude && chmod +x /usr/local/bin/claude; \
    elif [ -f /root/.local/bin/claude ]; then \
        cp /root/.local/bin/claude /usr/local/bin/claude && chmod +x /usr/local/bin/claude; \
    fi && \
    claude --version || true

# GitHub CLI.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && apt-get install -y --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*

# Google Chrome.
RUN curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
        -o /tmp/chrome.deb && \
    apt-get update && apt-get install -y --no-install-recommends /tmp/chrome.deb && \
    rm -f /tmp/chrome.deb && \
    rm -rf /var/lib/apt/lists/* && \
    rm -f /usr/local/bin/chromium

# ═══════════════════════════════════════════════════════════════════
# Stage: system - configuration/runtime layer over base-plus.
# ═══════════════════════════════════════════════════════════════════
FROM base-plus AS system

# KasmVNC UI customisation.
COPY kasm/custom.css /usr/share/kasmvnc/www/assets/custom.css
COPY kasm/patch.sh /tmp/kasm-patch.sh
RUN chmod +x /tmp/kasm-patch.sh && /tmp/kasm-patch.sh && rm /tmp/kasm-patch.sh

# Desktop wallpapers.
RUN set -eux; \
    wallpaper_dir=/usr/share/backgrounds/simpledesktops; \
    mkdir -p "$wallpaper_dir"; \
    for url in \
        "https://static.simpledesktops.com/uploads/desktops/2020/06/28/Big_Sur_Simple.png" \
        "https://static.simpledesktops.com/uploads/desktops/2020/06/10/Adidas_Blue.png" \
        "https://static.simpledesktops.com/uploads/desktops/2016/12/05/Untitled-1-03-01.png" \
        "https://static.simpledesktops.com/uploads/desktops/2016/09/01/Sunset.png" \
        "https://static.simpledesktops.com/uploads/desktops/2015/09/23/Take_OFF.png" \
        "https://static.simpledesktops.com/uploads/desktops/2015/06/26/Overlap.png" \
        "https://static.simpledesktops.com/uploads/desktops/2015/06/02/image_1.png" \
        "https://static.simpledesktops.com/uploads/desktops/2015/03/02/mountains-on-mars.png"; do \
        curl -fsSL "$url" -o "$wallpaper_dir/$(basename "$url")"; \
    done

# User + access configuration belongs to runtime/config layer.
RUN if id -u agent >/dev/null 2>&1; then \
        :; \
    elif id -u ubuntu >/dev/null 2>&1; then \
        usermod -l agent -d /home/agent -m ubuntu && groupmod -n agent ubuntu; \
    else \
        groupadd --system agent && useradd --system --create-home --home-dir /home/agent --gid agent --shell /bin/bash agent; \
    fi && \
    mkdir -p /home/agent/.vnc /home/agent/.config /home/agent/.local/share/applications && \
    chown -R agent:agent /home/agent

ENV HOME=/home/agent

# Sudo configuration belongs to the runtime/config layer.
RUN mkdir -p /etc/sudoers.d /home/agent && \
    echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent && \
    chmod 0440 /etc/sudoers.d/agent && \
    touch /home/agent/.sudo_as_admin_successful /home/agent/.hushlogin && \
    chown agent:agent /home/agent/.sudo_as_admin_successful /home/agent/.hushlogin

# Chrome preferences.
RUN mkdir -p /home/agent/.config/google-chrome/Default && \
    printf '{\n  "browser": {\n    "has_seen_welcome_page": true,\n    "check_default_browser": false\n  },\n  "bookmark_bar": { "show_on_all_tabs": false },\n  "distribution": {\n    "skip_first_run_ui": true,\n    "show_welcome_page": false,\n    "import_bookmarks": false,\n    "make_chrome_default_for_user": false,\n    "suppress_first_run_default_browser_prompt": true\n  }\n}' \
    > /home/agent/.config/google-chrome/Default/Preferences && \
    touch /home/agent/.config/google-chrome/"First Run" && \
    chown -R agent:agent /home/agent/.config/google-chrome

# Suppress default-browser prompt via managed policy.
RUN mkdir -p /etc/opt/chrome/policies/managed && \
    printf '{\n  "DefaultBrowserSettingEnabled": false,\n  "BrowserSignin": 0,\n  "HomepageLocation": "file:///opt/browser/index.html",\n  "HomepageIsNewTabPage": false,\n  "ShowHomeButton": true,\n  "RestoreOnStartup": 4,\n  "RestoreOnStartupURLs": [\n    "file:///opt/browser/index.html"\n  ]\n}' \
    > /etc/opt/chrome/policies/managed/chrome-policy.json

# Register Chrome as the default browser (system-level alternatives).
RUN mkdir -p /home/agent/.local/share/applications && \
    chown -R agent:agent /home/agent/.local && \
    update-alternatives --install /usr/bin/x-www-browser x-www-browser /opt/google/chrome/google-chrome 200 2>/dev/null || true && \
    update-alternatives --set x-www-browser /opt/google/chrome/google-chrome 2>/dev/null || true

# @note MIME associations and xdg defaults are configured in init.sh at
# runtime so they work in both Docker local and rootfs deployments.
# The Chrome wrapper lives in shell/ and is copied below.
ENV BROWSER=chromium

# Openbox config - dark minimal theme with tint2 panel.
COPY openbox/rc.xml /etc/xdg/openbox/rc.xml
COPY openbox/menu.xml /etc/xdg/openbox/menu.xml
COPY openbox/autostart /etc/xdg/openbox/autostart
COPY cortile/cortilectl /usr/local/bin/cortilectl
COPY shell/welcome /usr/local/bin/welcome
COPY shell/chromium /usr/local/bin/chromium
RUN mkdir -p /etc/bash.bashrc.d
COPY shell/bashrc /etc/bash.bashrc.d/pantalk-prompt.sh
RUN echo '[ -d /etc/bash.bashrc.d ] && for f in /etc/bash.bashrc.d/*.sh; do . "$f"; done' >> /etc/bash.bashrc
COPY browser /opt/browser
COPY config/pantalk.yaml /usr/local/share/station/pantalk-config.yaml
COPY openbox/theme /usr/share/themes/Triste-Crimson/openbox-3
COPY tint2/tint2rc /etc/xdg/tint2/tint2rc
RUN chmod +x /etc/xdg/openbox/autostart /usr/local/bin/cortilectl /usr/local/bin/welcome \
    /usr/local/bin/chromium

# Ensure a desktop entry exists for openbox-session so KasmVNC's
# select-de mechanism can discover and start it.
RUN mkdir -p /usr/share/xsessions && \
    printf '[Desktop Entry]\nName=Openbox\nExec=openbox-session\nType=Application\n' \
    > /usr/share/xsessions/openbox.desktop

# KasmVNC configuration.
USER agent

# Default Cortile config: floating by default, user enables tiling on demand.
RUN mkdir -p "$HOME/.config/cortile"
COPY --chown=agent:agent cortile/cortile-config.toml /home/agent/.config/cortile/config.toml

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
    -subj "/CN=agent" 2>/dev/null

# VNC password.
RUN bash -c 'echo -e "kasmvnc\nkasmvnc\n" | kasmvncpasswd -u agent -wo'

EXPOSE 6901
WORKDIR /workspace
VOLUME ["/workspace", "/home/agent/.config/pantalk", "/home/agent/.local/share/pantalk", "/home/agent/.codex", "/home/agent/.claude"]


# ═══════════════════════════════════════════════════════════════════
# Target: station - independently runnable Pantalk environment.
# ═══════════════════════════════════════════════════════════════════
FROM system AS station

USER root

COPY init.sh /init
RUN chmod +x /init

HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=5 \
    CMD curl -fsS http://127.0.0.1:6901/ >/dev/null || exit 1
ENTRYPOINT ["/init"]
