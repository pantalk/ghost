#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
overlay_test_dir="$(mktemp -d)"
workspace_test_dir="$(mktemp -d)"
trap 'rm -rf "$overlay_test_dir" "$workspace_test_dir"' EXIT

legacy_names=(
    "Pantalk St""ation"
    "pantalk/st""ation"
    "pantalk-st""ation"
    "ST""ATION_"
    "[st""ation]"
    "st""ation-panel"
    "#st""ation"
    "Pantalk N""ode"
    "pantalk/n""ode"
    "pantalk-n""ode"
    "N""ODE_IMAGE"
    "N""ODE_PLATFORM"
    "N""ODE_BIND_ADDRESS"
    "N""ODE_PORT"
    "N""ODE_RESOLUTION"
    "N""ODE_VNC_STATS"
    "@n""ode"
    "/home/n""ode"
    "n""ode-panel"
    "#n""ode"
)
for legacy_name in "${legacy_names[@]}"; do
    if grep --recursive --fixed-strings "$legacy_name" "$project_dir" \
        --exclude='test-ghost.sh' \
        --exclude='*.ico' \
        --exclude='*.png'; then
        echo "Legacy product namespace remains: $legacy_name" >&2
        exit 1
    fi
done

for legacy_glob in \
    "*st""ation*" \
    "test-n""ode.sh" \
    "n""ode-panel-status" \
    "pantalk-n""ode.svg"; do
    if find "$project_dir" -iname "$legacy_glob" -print -quit | grep -q .; then
        echo "A legacy product filename remains: $legacy_glob" >&2
        exit 1
    fi
done

overlay_dir="$project_dir/overlay"

normalized_menu="$(
    tr '\n\t' '  ' < "$overlay_dir/etc/xdg/openbox/menu.xml" | tr -s ' '
)"

grep -Fq 'agent-runtime-login codex' <<<"$normalized_menu"
grep -Fq 'agent-runtime-login claude' <<<"$normalized_menu"
grep -Fq 'agent-runtime-login kimi' <<<"$normalized_menu"
grep -Fq 'kitty -e ranger /workspace' <<<"$normalized_menu"
grep -Fq 'desktop-welcome' <<<"$normalized_menu"

# The workspace seed. The desktop base copies this directory into /workspace on
# boot without replacing files already there, so it reaches new volumes and
# upgraded ones alike.
seed="$overlay_dir/usr/local/share/launcher-desktop/workspace"
grep -Fq '# Pantalk Ghost Workspace' "$seed/AGENT.md"
cp --archive --update=none "$seed/." "$workspace_test_dir/"
cmp "$seed/AGENT.md" "$workspace_test_dir/AGENT.md"
printf 'custom workspace instructions\n' > "$workspace_test_dir/AGENT.md"
cp --archive --update=none "$seed/." "$workspace_test_dir/"
grep -Fxq 'custom workspace instructions' "$workspace_test_dir/AGENT.md"

# The browser landing page.
landing="$overlay_dir/opt/browser/index.html"
grep -Fq 'background: #000;' "$landing"
grep -Fq '░       ░░░░      ░░░' "$landing"
if grep -Fq 'Welcome to Pantalk Ghost' "$landing"; then
    echo "The obsolete browser welcome card is still present." >&2
    exit 1
fi

# Pantalk state lives on volumes the base is told about through
# DESKTOP_PERSISTENT_PATHS, so those two lists must agree.
grep -Fq '/home/agent/.kimi' "$project_dir/Dockerfile"
grep -Fq 'DESKTOP_PERSISTENT_PATHS=' "$project_dir/Dockerfile"
grep -Fq '$(VOLUME_PREFIX)-kimi:/home/agent/.kimi' "$project_dir/Makefile"
grep -Fq 'ghost-kimi:/home/agent/.kimi' \
    "$project_dir/deployments/ergo/compose.yaml"
grep -Fq 'ghost-kimi:/home/agent/.kimi' \
    "$project_dir/deployments/mattermost/compose.yaml"

# The local workflow follows the shared Launcher image workflow: run builds the
# image, the interactive desktop uses 6901, and the preview uses 6902.
grep -Fq 'RUN_PORT ?= 6901' "$project_dir/Makefile"
grep -Fq 'RUN_PREVIEW_PORT ?= 6902' "$project_dir/Makefile"
grep -Fq 'run: build' "$project_dir/Makefile"
grep -Fq -- '--publish "$(BIND_ADDRESS):$(RUN_PORT):6901"' \
    "$project_dir/Makefile"
grep -Fq -- '--publish "$(BIND_ADDRESS):$(RUN_PREVIEW_PORT):6902"' \
    "$project_dir/Makefile"
grep -Fq -- '--publish 127.0.0.1:6901:6901' "$project_dir/README.md"
grep -Fq -- '--publish 127.0.0.1:6902:6902' "$project_dir/README.md"
grep -Fq 'RUN_PORT=8080 RUN_PREVIEW_PORT=8081 make run' \
    "$project_dir/README.md"
for deployment in ergo mattermost; do
    grep -Fq 'GHOST_PORT=6901' \
        "$project_dir/deployments/$deployment/.env.example"
    grep -Fq 'GHOST_PREVIEW_PORT=6902' \
        "$project_dir/deployments/$deployment/.env.example"
    grep -Fq '${GHOST_PORT:-6901}:6901' \
        "$project_dir/deployments/$deployment/compose.yaml"
    grep -Fq '${GHOST_PREVIEW_PORT:-6902}:6902' \
        "$project_dir/deployments/$deployment/compose.yaml"
done
if grep --recursive --fixed-strings '6902:6901' "$project_dir" \
    --exclude='test-ghost.sh' \
    --exclude='CHANGELOG.md'; then
    echo "The desktop is still mapped through the preview port." >&2
    exit 1
fi

# The desktop harness and the chat-side agents must agree about the workspace:
# both work there unattended, so neither should sit on a trust prompt.
trust="$overlay_dir/etc/desktop/startup.d/05-agent-runtime-trust"
grep -Fq 'GHOST_TRUST_WORKSPACE' "$trust"
grep -Fq 'GHOST_CODEX_SANDBOX_MODE' "$trust"
grep -Fq 'sandbox_mode = "%s"' "$trust"
grep -Fq 'GHOST_CODEX_SANDBOX_MODE' "$project_dir/README.md"
grep -Fq 'trust_level = "trusted"' "$trust"
grep -Fq 'hasTrustDialogAccepted' "$trust"
grep -Fq 'GHOST_HARNESS_WORKDIR:-/workspace' "$trust"
grep -Fq 'GHOST_HARNESS_WORKDIR:-/workspace' \
    "$overlay_dir/usr/local/bin/desktop-harness"
# Apple `container` runs the desktop as root after detecting fixed-ownership
# mounts. That path must copy configuration without requesting an ownership
# change which VirtioFS will reject.
grep -Fq 'if [ "$runtime_user" = root ]; then' "$trust"
grep -Fq 'if [ "$runtime_user" != root ]; then' "$trust"
grep -Fq 'write_runtime_config()' "$trust"
! grep -Fq 'install_as_runtime_user' "$trust"

# Pantalk itself: the starter config is seeded and the daemon is supervised
# from the base's pre-session hook.
pantalk_hook="$overlay_dir/etc/desktop/startup.d/10-pantalk"
grep -Fq 'PANTALK_AUTOSTART' "$pantalk_hook"
grep -Fq 'exec pantalkd --config' "$pantalk_hook"
grep -Fq 'setsid su' "$pantalk_hook"
grep -Fq 'created starter Pantalk configuration' "$pantalk_hook"

# Config volumes survive image upgrades. A config seeded by an older Ghost
# image must retain the user's settings while its obsolete home path moves to
# the runtime home used by the current image.
legacy_config="$overlay_test_dir/pantalk/config.yaml"
mkdir -p "$(dirname "$legacy_config")"
cat > "$legacy_config" <<'EOF'
server:
  notification_history_size: 321
  media:
    backend: fs
    path: /home/ghost/.local/share/pantalk/media
custom_setting: retained
EOF

DESKTOP_RUNTIME_USER="$(id -un)" \
    PANTALK_CONFIG="$legacy_config" \
    PANTALK_AUTOSTART=false \
    "$pantalk_hook" >/dev/null

test "$(yq -r '.server.media.path' "$legacy_config")" = \
    '/home/agent/.local/share/pantalk/media'
test "$(yq -r '.server.notification_history_size' "$legacy_config")" = 321
test "$(yq -r '.custom_setting' "$legacy_config")" = retained
legacy_backup="${legacy_config}.ghost-home.bak"
test -s "$legacy_backup"
test "$(yq -r '.server.media.path' "$legacy_backup")" = \
    '/home/ghost/.local/share/pantalk/media'

# A second startup is a no-op and must not replace the original backup.
backup_checksum="$(sha256sum "$legacy_backup")"
DESKTOP_RUNTIME_USER="$(id -un)" \
    PANTALK_CONFIG="$legacy_config" \
    PANTALK_AUTOSTART=false \
    "$pantalk_hook" >/dev/null
test "$(sha256sum "$legacy_backup")" = "$backup_checksum"

# Terminals start in the workspace. Openbox chdirs to $HOME at startup whatever
# directory it was started from, so this cannot be set for the session and has
# to happen in the shell, which every terminal passes through. Both guards are
# load-bearing: without the PS1 test it would move non-interactive shells and
# break scripts that depend on their working directory, and without the $PWD
# test it would override a directory somebody chose on purpose.
bashrc="$overlay_dir/etc/bash.bashrc.d/pantalk-prompt.sh"
grep -Fq "local neon_green='\\[\\e[38;5;46m\\]'" "$bashrc"
grep -Fq 'PS1="${neon_green}@\\u ' "$bashrc"
grep -Fq 'cd /workspace' "$bashrc"
grep -Fq '[ -n "${PS1:-}" ]' "$bashrc"
grep -Fq '[ "$PWD" = "$HOME" ]' "$bashrc"

grep -Fq 'panel_items = PTSEC' "$overlay_dir/etc/xdg/tint2/tint2rc"
grep -Fq 'execp_command = desktop-panel-status' \
    "$overlay_dir/etc/xdg/tint2/tint2rc"
test -s "$overlay_dir/usr/share/kasmvnc/www/assets/favicon.svg"

# The wallpaper drop-in the base resolves at session start. It must contain no
# XML comment: the imlib2 loader feh uses rejects any SVG with one, and the
# desktop then comes up with no wallpaper at all.
wallpaper="$overlay_dir/usr/share/backgrounds/desktop-wallpaper.svg"
grep -Fq '#24DBC9' "$wallpaper"
if grep -Fq '<!--' "$wallpaper"; then
    echo "The wallpaper contains an XML comment; feh will refuse to load it." >&2
    exit 1
fi
if grep -Fq '<text' "$wallpaper" || grep -Fq 'M115.199 384V204.8' "$wallpaper"; then
    echo "The clean desktop wallpaper still contains logo artwork." >&2
    exit 1
fi

# The mascot overlay is client-side only: it must be injected into the KasmVNC
# page and must never take pointer events away from the remote desktop. The
# base's kasm-patch does not know about it, so this image injects it itself -
# after kasm-patch, because both rewrite the same <head>.
mascot_js="$overlay_dir/usr/share/kasmvnc/www/assets/mascot.js"
mascot_css="$overlay_dir/usr/share/kasmvnc/www/assets/mascot.css"
injector="$overlay_dir/usr/local/bin/kasm-mascot"
grep -Fq 'RUN kasm-patch "Pantalk Ghost" && kasm-mascot' "$project_dir/Dockerfile"
grep -Fq 'assets/mascot.css' "$injector"
grep -Fq 'assets/mascot.js' "$injector"
grep -Fq 'the mascot overlay was not injected' "$injector"
# KasmVNC serves these assets with no cache-control, etag, or last-modified,
# so unversioned URLs leave browsers running a stale overlay against a freshly
# built image. The URLs must carry a content hash.
grep -Fq 'sha256sum "$www/assets/mascot.js"' "$injector"
grep -Fq 'mascot.css?v=${mascot_css_version}' "$injector"
grep -Fq 'mascot.js?v=${mascot_js_version}' "$injector"
# The ghost itself is the click target; the blurred glow around it must stay
# click-through so the dead zone over the desktop is no wider than the ghost.
grep -Fq 'pointer-events: auto;' "$mascot_css"
grep -Fq 'pointer-events: none;' "$mascot_css"
# Clicking synthesises the same key the desktop base binds to desktop-harness.
grep -Fq "key(target, 'keydown', 'KeyG', 'g', true, true)" "$mascot_js"
# Every modifier the click presses must be released again, or the desktop is
# left treating later keystrokes as shortcuts.
grep -Fq "key(target, 'keyup', 'ShiftLeft', 'Shift', true, false)" "$mascot_js"
grep -Fq "key(target, 'keyup', 'ControlLeft', 'Control', false, false)" "$mascot_js"
# Only Control and Shift survive noVNC's Mac keyboard normalisation unchanged.
# Alt arrives as an AltGr-class modifier and Super arrives as Alt, so either
# one silently breaks the Openbox grab for Mac clients while still working on
# Linux - the exact failure that is invisible to testing from Linux.
if grep -Fq "'AltLeft'" "$mascot_js" ||
    grep -Fq "'AltRight'" "$mascot_js" ||
    grep -Fq "'MetaLeft'" "$mascot_js" ||
    grep -Fq 'metaKey:' "$mascot_js" ||
    grep -Fq 'altKey:' "$mascot_js"; then
    echo "The mascot shortcut uses a modifier noVNC rewrites for Mac clients." >&2
    exit 1
fi
# The float keyframes must stay identical to .platform-float on the site.
grep -Fq 'translateY(-6px)' "$mascot_css"
grep -Fq 'animation: pantalk_mascot_float 3s ease-in-out infinite;' "$mascot_css"
# The mascot is unframed: no card border or fill may creep back in.
if grep -Fq 'pantalk_mascot_card' "$mascot_css" ||
    grep -Fq 'pantalk_mascot_card' "$mascot_js"; then
    echo "The mascot is framed in a card again." >&2
    exit 1
fi

# Nothing here may re-implement what the desktop base already provides.
for owned_by_base in \
    'GTK_THEME=' \
    'G_RESOURCE_OVERLAYS=' \
    'generate-resource-overlay.py' \
    'kasmvncserver' \
    'CORTILE_VERSION' \
    'KASMVNC_VERSION' \
    'google-chrome-stable_current_amd64.deb' \
    'BrowserThemeColor'
do
    if grep -Fq -- "$owned_by_base" "$project_dir/Dockerfile"; then
        echo "Dockerfile re-implements '$owned_by_base', which the base owns." >&2
        exit 1
    fi
done

for stale_path in openbox cortile kasm gtk tint2 wallpaper shell config init.sh; do
    if [ -e "$project_dir/$stale_path" ]; then
        echo "$stale_path survived the move to the desktop base." >&2
        exit 1
    fi
done

panel_status="$overlay_dir/usr/local/bin/desktop-panel-status"
mock_bin="$(mktemp -d)"
trap 'rm -rf "$mock_bin"' EXIT

cat > "$mock_bin/pgrep" <<'EOF'
#!/bin/bash
exit "${MOCK_PGREP_EXIT:-1}"
EOF
chmod +x "$mock_bin/pgrep"

running_output="$(
    MOCK_PGREP_EXIT=0 PATH="$mock_bin:$PATH" "$panel_status"
)"
grep -Fq 'running' <<<"$running_output"

stopped_output="$(
    MOCK_PGREP_EXIT=1 PATH="$mock_bin:$PATH" "$panel_status"
)"
grep -Fq 'stopped' <<<"$stopped_output"

# desktop-harness resolves the harness that agent-runtime-login recorded, and
# degrades predictably when nothing has been selected yet.
harness="$overlay_dir/usr/local/bin/desktop-harness"
harness_state="$(mktemp -d)"
trap 'rm -rf "$mock_bin" "$harness_state"' EXIT

grep -Fq 'codex' <<<"$(
    GHOST_HARNESS_STATE_DIR="$harness_state" "$harness" --dry-run
)"

printf 'claude\n' > "$harness_state/harness"
selected="$(GHOST_HARNESS_STATE_DIR="$harness_state" "$harness" --dry-run)"
grep -Fq 'claude claude Claude Harness' <<<"$selected"

# A harness must start in the workspace, not the session's home directory, so
# the desktop and the chat-side agents act on the same tree.
grep -Fq '/workspace' <<<"$selected"
override="$(
    GHOST_HARNESS_STATE_DIR="$harness_state" GHOST_HARNESS_WORKDIR=/tmp \
        "$harness" --dry-run
)"
grep -Fq '/tmp' <<<"$override"

printf 'kimi\n' > "$harness_state/harness"
selected="$(GHOST_HARNESS_STATE_DIR="$harness_state" "$harness" --dry-run)"
grep -Fq 'kimi kimi Kimi Harness' <<<"$selected"

# A selection left by an older image must not be trusted blindly.
printf 'not-a-harness\n' > "$harness_state/harness"
selected="$(GHOST_HARNESS_STATE_DIR="$harness_state" "$harness" --dry-run)"
grep -Fq 'codex codex Codex Harness' <<<"$selected"

# An unusable fallback must still resolve to something launchable.
selected="$(
    GHOST_HARNESS_STATE_DIR="$harness_state" GHOST_HARNESS_DEFAULT=bogus \
        "$harness" --dry-run
)"
grep -Fq 'codex codex Codex Harness' <<<"$selected"

rm -f "$harness_state/harness"
selected="$(
    GHOST_HARNESS_STATE_DIR="$harness_state" GHOST_HARNESS_DEFAULT=claude \
        "$harness" --dry-run
)"
grep -Fq 'claude claude Claude Harness' <<<"$selected"

# Signing in selects the harness; a status check is not a sign-in and must
# leave the previous selection alone.
login="$overlay_dir/usr/local/bin/agent-runtime-login"
cat > "$mock_bin/codex" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$mock_bin/claude" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$mock_bin/codex" "$mock_bin/claude"

GHOST_HARNESS_STATE_DIR="$harness_state" PATH="$mock_bin:$PATH" \
    "$login" claude subscription >/dev/null
grep -Fqx 'claude' "$harness_state/harness"

GHOST_HARNESS_STATE_DIR="$harness_state" PATH="$mock_bin:$PATH" \
    "$login" codex status >/dev/null
grep -Fqx 'claude' "$harness_state/harness"

GHOST_HARNESS_STATE_DIR="$harness_state" PATH="$mock_bin:$PATH" \
    "$login" codex device >/dev/null
grep -Fqx 'codex' "$harness_state/harness"

echo "Ghost desktop tests passed."
