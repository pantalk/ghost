#!/bin/bash
# Pantalk Ghost container entrypoint.
# Starts Pantalk and the original Openbox/KasmVNC desktop.

set -euo pipefail

export HOME=/home/ghost
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"

ghost_uid="$(id -u ghost)"
export XDG_RUNTIME_DIR="/run/user/${ghost_uid}"
export PANTALK_CONFIG="${PANTALK_CONFIG:-$HOME/.config/pantalk/config.yaml}"

resolution="${GHOST_RESOLUTION:-1920x1080}"
if [[ ! "$resolution" =~ ^[0-9]{3,5}x[0-9]{3,5}$ ]]; then
    echo "[ghost] invalid GHOST_RESOLUTION: $resolution" >&2
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
    "$HOME/.kimi" \
    "$XDG_RUNTIME_DIR" \
    /workspace \
    /var/log/ghost \
    /tmp/.X11-unix

# Keep the durable workspace and the desktop user's home available as Ranger
# bookmarks without replacing any bookmarks the user has already assigned.
ranger_data_dir="$XDG_DATA_HOME/ranger"
ranger_bookmarks="$ranger_data_dir/bookmarks"
mkdir -p "$ranger_data_dir"
touch "$ranger_bookmarks"
if ! grep -q '^W:' "$ranger_bookmarks"; then
    printf 'W:/workspace\n' >> "$ranger_bookmarks"
fi
if ! grep -q '^H:' "$ranger_bookmarks"; then
    printf 'H:%s\n' "$HOME" >> "$ranger_bookmarks"
fi

# Named-volume ownership only needs normalizing once. Recursing through the
# workspace and runtime state on every boot becomes minutes of startup latency
# after they contain real repositories and session histories.
persistent_paths=(
    "$HOME/.config/pantalk"
    "$HOME/.local/share/pantalk"
    "$HOME/.codex"
    "$HOME/.claude"
    "$HOME/.kimi"
    /workspace
)
ownership_stamp="$HOME/.config/pantalk/.ownership-normalized"

chown ghost:ghost \
    "$HOME" \
    "$HOME/.vnc" \
    "$HOME/.config" \
    "$HOME/.local" \
    "$HOME/.local/share" \
    "$HOME/.local/share/applications" \
    "$ranger_data_dir" \
    "$ranger_bookmarks" \
    "${persistent_paths[@]}" \
    "$XDG_RUNTIME_DIR" \
    /var/log/ghost

if [ ! -e "$ownership_stamp" ]; then
    chown -R ghost:ghost "${persistent_paths[@]}" /var/log/ghost
    touch "$ownership_stamp"
    chown ghost:ghost "$ownership_stamp"
    echo "[ghost] normalized ownership of the persistent volumes"
fi

chmod 700 "$XDG_RUNTIME_DIR" "$HOME/.config/pantalk"
chmod 1777 /tmp/.X11-unix

# The KasmVNC launcher validates Ubuntu's snake-oil key even when TLS is
# disabled. Its directory is restricted to members of the ssl-cert group.
if getent group ssl-cert >/dev/null 2>&1; then
    usermod -a -G ssl-cert ghost
fi

if [ ! -s "$PANTALK_CONFIG" ]; then
    install -m 0600 -o ghost -g ghost \
        /usr/local/share/ghost/pantalk-config.yaml "$PANTALK_CONFIG"
    chown ghost:ghost "$PANTALK_CONFIG"
    echo "[ghost] created starter Pantalk configuration"
elif yq -e '
    (.bots | length) == 2 and
    .bots[0].name == "codex" and
    .bots[0].type == "irc" and
    .bots[0].endpoint == "127.0.0.1:6667" and
    .bots[1].name == "claude" and
    .bots[1].type == "irc" and
    .bots[1].endpoint == "127.0.0.1:6667"
' "$PANTALK_CONFIG" >/dev/null 2>&1; then
    cp --no-clobber "$PANTALK_CONFIG" "${PANTALK_CONFIG}.ghost-irc.bak"
    install -m 0600 -o ghost -g ghost \
        /usr/local/share/ghost/pantalk-config.yaml "$PANTALK_CONFIG"
    echo "[ghost] migrated the bundled IRC configuration to the local starter"
fi

# Codex and Claude Code each prompt once per directory before working in it
# ("Do you trust the contents of this directory?"). The harness opened from the
# desktop starts in the workspace, and the chat-side agents already work there
# unattended - the starter config gives them workdir: /workspace with
# approval_policy: never - so prompting only the desktop path leaves the two
# disagreeing about the same directory. Record the decision instead of asking.
#
# This grants no access the chat path does not already have. Set
# GHOST_TRUST_WORKSPACE=false to leave both prompts in place.
harness_workdir="${GHOST_HARNESS_WORKDIR:-/workspace}"
codex_config="$HOME/.codex/config.toml"

# Codex sandboxes the commands it runs with bubblewrap, and warns when it has to
# fall back to its bundled copy. Neither copy can work here: the container blocks
# unprivileged user namespaces, so bwrap cannot create one, and installing the
# distro package only adds a second binary that fails the same way. Declare the
# mode that matches reality rather than leaving a config that implies an
# isolation boundary which is not there - the boundary is the container itself,
# which is the posture documented in the README.
#
# Set GHOST_CODEX_SANDBOX_MODE to read-only or workspace-write to choose a
# different mode, or to an empty value to leave the setting out entirely.
codex_sandbox_mode="${GHOST_CODEX_SANDBOX_MODE-danger-full-access}"
if [ -n "$codex_sandbox_mode" ] &&
    ! grep -Eq '^sandbox_mode *=' "$codex_config" 2>/dev/null; then
    codex_sandbox_tmp="$(mktemp)"
    # Prepended, not appended: sandbox_mode is a top-level key, and TOML assigns
    # any key following a [table] header to that table. The trust block below
    # writes [projects."..."] tables, so appending would quietly turn this into a
    # per-project setting instead of a global one.
    {
        printf 'sandbox_mode = "%s"\n\n' "$codex_sandbox_mode"
        [ -s "$codex_config" ] && cat "$codex_config"
    } > "$codex_sandbox_tmp"
    install -m 0600 -o ghost -g ghost "$codex_sandbox_tmp" "$codex_config"
    rm -f "$codex_sandbox_tmp"
    echo "[ghost] set Codex sandbox_mode=$codex_sandbox_mode" \
        "(no usable bubblewrap in a container)"
fi

if [ "${GHOST_TRUST_WORKSPACE:-true}" = "true" ]; then
    if ! grep -Fq "[projects.\"$harness_workdir\"]" "$codex_config" 2>/dev/null; then
        printf '\n[projects."%s"]\ntrust_level = "trusted"\n' \
            "$harness_workdir" >> "$codex_config"
        chown ghost:ghost "$codex_config"
        echo "[ghost] recorded $harness_workdir as trusted for Codex"
    fi

    claude_config="$HOME/.claude.json"
    if ! jq -e --arg dir "$harness_workdir" \
        '.projects[$dir].hasTrustDialogAccepted == true' \
        "$claude_config" >/dev/null 2>&1; then
        [ -s "$claude_config" ] || echo '{}' > "$claude_config"
        claude_trust_tmp="$(mktemp)"
        # Leave the file untouched if it is not valid JSON rather than
        # replacing a config the operator may have hand-written.
        if jq --arg dir "$harness_workdir" \
            '.projects[$dir].hasTrustDialogAccepted = true' \
            "$claude_config" > "$claude_trust_tmp" 2>/dev/null; then
            install -m 0600 -o ghost -g ghost \
                "$claude_trust_tmp" "$claude_config"
            echo "[ghost] recorded $harness_workdir as trusted for Claude Code"
        fi
        rm -f "$claude_trust_tmp"
    fi
fi

# Use a GPU only when the host exposes a render node and the desktop user can
# open it. A passed-through node is normally root:render 0660 and the host's
# render group may not exist in this image, so presence alone does not mean it
# is usable.
gpu_node=""
gpu_node_blocked=""
for node in /dev/dri/renderD*; do
    [ -e "$node" ] || continue
    printf -v node_q '%q' "$node"
    if su -s /bin/bash -c "test -r $node_q && test -w $node_q" ghost; then
        gpu_node="$node"
        break
    fi
    gpu_node_blocked="$node"
done

if [ -n "$gpu_node" ]; then
    gpu_config="  gpu:
    hw3d: true
    drinode: $gpu_node"
    echo "[ghost] GPU acceleration enabled via $gpu_node"
else
    gpu_config="  gpu:
    hw3d: false"
    if [ -n "$gpu_node_blocked" ]; then
        echo "[ghost] $gpu_node_blocked is not readable by the desktop user;" \
            "using software rendering"
    else
        echo "[ghost] no GPU render node found; using software rendering"
    fi
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
if [ "${GHOST_VNC_STATS:-false}" = "true" ]; then
    cat >> "$HOME/.vnc/kasmvnc.yaml" <<'YAML'

logging:
  log_writer_name: EncodeManager
  log_dest: logfile
  level: 100
YAML
    echo "[ghost] KasmVNC encoder statistics enabled"
fi

cat > "$HOME/.vnc/xstartup" <<'XSTARTUP'
#!/bin/bash
exec openbox-session
XSTARTUP
chmod +x "$HOME/.vnc/xstartup"
touch "$HOME/.vnc/.de-was-selected"
chown -R ghost:ghost "$HOME/.vnc"

# KasmVNC checks for these files even though browser authentication and TLS are
# disabled for this loopback-only local image.
# shellcheck disable=SC2016
su -s /bin/bash -c '
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$HOME/.vnc/self.pem" \
        -out "$HOME/.vnc/self.pem" \
        -subj "/CN=pantalk-ghost" >/dev/null 2>&1
    printf "ghost\nghost\n" | kasmvncpasswd -u ghost -wo >/dev/null 2>&1 || true
' ghost

# shellcheck disable=SC2329
cleanup() {
    echo "[ghost] stopping"
    su -s /bin/bash -c 'kasmvncserver -kill :1 >/dev/null 2>&1 || true' ghost
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
    " ghost >>/var/log/ghost/pantalkd.log 2>&1 &
    echo "[ghost] pantalkd started"
fi

su -s /bin/bash -c 'kasmvncserver -kill :1 >/dev/null 2>&1 || true' ghost
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
" ghost >>/var/log/ghost/kasmvnc.log 2>&1 &

for attempt in $(seq 1 40); do
    if curl -fsS http://127.0.0.1:6901/ >/dev/null 2>&1; then
        echo "[ghost] ready at http://localhost:6901"
        break
    fi
    if [ "$attempt" -eq 40 ]; then
        echo "[ghost] KasmVNC did not become ready" >&2
        tail -n 100 /var/log/ghost/kasmvnc.log >&2 || true
        exit 1
    fi
    sleep 1
done

while curl -fsS http://127.0.0.1:6901/ >/dev/null 2>&1; do
    sleep 5
done

echo "[ghost] browser environment stopped unexpectedly" >&2
exit 1
