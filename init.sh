#!/bin/bash
# Pantalk Station container entrypoint.
# Starts Pantalk and the original Openbox/KasmVNC desktop.

set -euo pipefail

export HOME=/home/agent
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"

agent_uid="$(id -u agent)"
export XDG_RUNTIME_DIR="/run/user/${agent_uid}"
export PANTALK_CONFIG="${PANTALK_CONFIG:-$HOME/.config/pantalk/config.yaml}"

resolution="${STATION_RESOLUTION:-1920x1080}"
if [[ ! "$resolution" =~ ^[0-9]{3,5}x[0-9]{3,5}$ ]]; then
    echo "[station] invalid STATION_RESOLUTION: $resolution" >&2
    exit 1
fi

width="${resolution%x*}"
height="${resolution#*x}"

mkdir -p \
    "$HOME/.vnc" \
    "$HOME/.config/pantalk" \
    "$HOME/.local/share/pantalk" \
    "$HOME/.local/share/applications" \
    "$HOME/.codex" \
    "$HOME/.claude" \
    "$XDG_RUNTIME_DIR" \
    /workspace \
    /var/log/station \
    /tmp/.X11-unix

chown -R agent:agent \
    "$HOME/.vnc" \
    "$HOME/.config/pantalk" \
    "$HOME/.local/share/pantalk" \
    "$HOME/.local/share/applications" \
    "$HOME/.codex" \
    "$HOME/.claude" \
    "$XDG_RUNTIME_DIR" \
    /workspace \
    /var/log/station
chmod 700 "$XDG_RUNTIME_DIR"
chmod 1777 /tmp/.X11-unix

# The KasmVNC launcher validates Ubuntu's snake-oil key even when TLS is
# disabled. Its directory is restricted to members of the ssl-cert group.
if getent group ssl-cert >/dev/null 2>&1; then
    usermod -a -G ssl-cert agent
fi

if [ ! -s "$PANTALK_CONFIG" ]; then
    install -m 0600 -o agent -g agent \
        /usr/local/share/station/pantalk-config.yaml "$PANTALK_CONFIG"
    chown agent:agent "$PANTALK_CONFIG"
    echo "[station] created starter Pantalk configuration"
elif yq -e '
    (.bots | length) == 2 and
    .bots[0].name == "codex" and
    .bots[0].type == "irc" and
    .bots[0].endpoint == "127.0.0.1:6667" and
    .bots[1].name == "claude" and
    .bots[1].type == "irc" and
    .bots[1].endpoint == "127.0.0.1:6667"
' "$PANTALK_CONFIG" >/dev/null 2>&1; then
    cp --no-clobber "$PANTALK_CONFIG" "${PANTALK_CONFIG}.station-irc.bak"
    install -m 0600 -o agent -g agent \
        /usr/local/share/station/pantalk-config.yaml "$PANTALK_CONFIG"
    echo "[station] migrated the bundled IRC configuration to the local starter"
fi

# Use a GPU when the host actually exposes one. KasmVNC always passes its
# -drinode default, but only emits -hw3d when hw3d is true, so the default is
# inert and the desktop silently renders in software. Hosts without a render
# node - Podman/Docker VMs on macOS and Windows, most CI - take the else branch
# and keep working exactly as before.
gpu_node=""
for node in /dev/dri/renderD*; do
    if [ -e "$node" ]; then
        gpu_node="$node"
        break
    fi
done

if [ -n "$gpu_node" ]; then
    gpu_config="  gpu:
    hw3d: true
    drinode: $gpu_node"
    echo "[station] GPU acceleration enabled via $gpu_node"
else
    gpu_config="  gpu:
    hw3d: false"
    echo "[station] no GPU render node found; using software rendering"
fi

cat > "$HOME/.vnc/kasmvnc.yaml" <<YAML
network:
  protocol: http
  ssl:
    require_ssl: false
  interface: 0.0.0.0
  websocket_port: 6901

desktop:
  resolution:
    width: $width
    height: $height
  pixel_depth: 24
$gpu_config

encoding:
  max_frame_rate: 30

security:
  brute_force_protection:
    blacklist_threshold: 0
YAML

# Optional encoder statistics. KasmVNC's EncodeManager writes "Framebuffer
# updates" and "Max encoding time during the last N frames" to the session log,
# which is how a session gets profiled without enabling authentication for the
# /api/get_bottleneck_stats endpoint. Off by default because level 100 is
# chatty.
#
# @note KasmVNC builds a single "writer:dest:level" argument from these three
# keys, so log_dest must be set explicitly and the writer name replaces rather
# than extends the default "*" - Xvnc's other log writers go quiet while this
# is enabled. "logfile" resolves to stdout, but kasmvncserver redirects Xvnc's
# stdout into its own per-session log at $HOME/.vnc/<hostname>:1.log, not into
# the container log - so `make logs` does not show these. Use `make vnc-log`.
if [ "${STATION_VNC_STATS:-false}" = "true" ]; then
    cat >> "$HOME/.vnc/kasmvnc.yaml" <<'YAML'

logging:
  log_writer_name: EncodeManager
  log_dest: logfile
  level: 100
YAML
    echo "[station] KasmVNC encoder statistics enabled"
fi

cat > "$HOME/.vnc/xstartup" <<'XSTARTUP'
#!/bin/bash
exec openbox-session
XSTARTUP
chmod +x "$HOME/.vnc/xstartup"
touch "$HOME/.vnc/.de-was-selected"
chown -R agent:agent "$HOME/.vnc"

# KasmVNC checks for these files even though browser authentication and TLS are
# disabled for this loopback-only local image.
# shellcheck disable=SC2016
su -s /bin/bash -c '
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$HOME/.vnc/self.pem" \
        -out "$HOME/.vnc/self.pem" \
        -subj "/CN=pantalk-station" >/dev/null 2>&1
    printf "station\nstation\n" | kasmvncpasswd -u agent -wo >/dev/null 2>&1 || true
' agent

# shellcheck disable=SC2329
cleanup() {
    echo "[station] stopping"
    su -s /bin/bash -c 'kasmvncserver -kill :1 >/dev/null 2>&1 || true' agent
    jobs -pr | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT INT TERM

if [ "${PANTALK_AUTOSTART:-true}" = "true" ]; then
    su -s /bin/bash -c "
        export HOME='$HOME'
        export XDG_CONFIG_HOME='$XDG_CONFIG_HOME'
        export XDG_DATA_HOME='$XDG_DATA_HOME'
        export XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR'
        export PANTALK_CONFIG='$PANTALK_CONFIG'
        exec pantalkd --config '$PANTALK_CONFIG'
    " agent >>/var/log/station/pantalkd.log 2>&1 &
    echo "[station] pantalkd started"
fi

su -s /bin/bash -c 'kasmvncserver -kill :1 >/dev/null 2>&1 || true' agent
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

su -s /bin/bash -c "
    export HOME='$HOME'
    export DISPLAY=:1
    export XDG_CONFIG_HOME='$XDG_CONFIG_HOME'
    export XDG_DATA_HOME='$XDG_DATA_HOME'
    export XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR'
    exec kasmvncserver :1 \
        -disableBasicAuth \
        -interface 0.0.0.0 \
        -websocketPort 6901 \
        -publicIP 127.0.0.1 \
        -geometry '$resolution' \
        -depth 24 \
        -httpd /usr/share/kasmvnc/www \
        -BlacklistThreshold 0 \
        -FreeKeyMappings
" agent >>/var/log/station/kasmvnc.log 2>&1 &

for attempt in $(seq 1 40); do
    if curl -fsS http://127.0.0.1:6901/ >/dev/null 2>&1; then
        echo "[station] ready at http://localhost:6901"
        break
    fi
    if [ "$attempt" -eq 40 ]; then
        echo "[station] KasmVNC did not become ready" >&2
        tail -n 100 /var/log/station/kasmvnc.log >&2 || true
        exit 1
    fi
    sleep 1
done

while curl -fsS http://127.0.0.1:6901/ >/dev/null 2>&1; do
    sleep 5
done

echo "[station] browser environment stopped unexpectedly" >&2
exit 1
