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
    if rg --hidden --fixed-strings "$legacy_name" "$project_dir" \
        --glob '!tests/test-ghost.sh' \
        --glob '!**/*.ico' \
        --glob '!**/*.png'; then
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

normalized_menu="$(
    tr '\n\t' '  ' < "$project_dir/openbox/menu.xml" | tr -s ' '
)"

grep -Fq 'agent-runtime-login codex' <<<"$normalized_menu"
grep -Fq 'agent-runtime-login claude' <<<"$normalized_menu"
grep -Fq 'agent-runtime-login kimi' <<<"$normalized_menu"
grep -Fq 'kitty -e ranger /workspace' <<<"$normalized_menu"

grep -Fq 'map ctrl+c copy_or_interrupt' "$project_dir/openbox/autostart"
grep -Fq 'map ctrl+v paste_from_clipboard' "$project_dir/openbox/autostart"
grep -Fq 'tint2 -c /etc/xdg/tint2/tint2rc' \
    "$project_dir/openbox/autostart"

grep -Fq 'ENV HOME=/home/ghost' "$project_dir/Dockerfile"
grep -Fq 'USER ghost' "$project_dir/Dockerfile"
grep -Fq \
    'COPY --chown=ghost:ghost workspace /usr/local/share/ghost/workspace' \
    "$project_dir/Dockerfile"
grep -Fq \
    'cp --archive --update=none "$workspace_seed_dir/." /workspace/' \
    "$project_dir/init.sh"
grep -Fq '# Pantalk Ghost Workspace' "$project_dir/workspace/AGENT.md"
cp --archive --update=none "$project_dir/workspace/." "$workspace_test_dir/"
cmp "$project_dir/workspace/AGENT.md" "$workspace_test_dir/AGENT.md"
printf 'custom workspace instructions\n' > "$workspace_test_dir/AGENT.md"
cp --archive --update=none "$project_dir/workspace/." "$workspace_test_dir/"
grep -Fxq 'custom workspace instructions' "$workspace_test_dir/AGENT.md"
grep -Fq 'background: #000;' "$project_dir/browser/index.html"
grep -Fq '░       ░░░░      ░░░' "$project_dir/browser/index.html"
if grep -Fq 'Welcome to Pantalk Ghost' "$project_dir/browser/index.html"; then
    echo "The obsolete browser welcome card is still present." >&2
    exit 1
fi
grep -Fq 'ENV GTK_THEME=PantalkGhost' "$project_dir/Dockerfile"
grep -Fq \
    'ENV G_RESOURCE_OVERLAYS=/org/gtk/libgtk=/usr/share/pantalk-ghost/gtk-overlay' \
    "$project_dir/Dockerfile"
grep -Fq \
    'COPY gtk/PantalkGhost /usr/share/themes/PantalkGhost' \
    "$project_dir/Dockerfile"
grep -Fq \
    'COPY gtk/generate-resource-overlay.py /tmp/generate-gtk-resource-overlay.py' \
    "$project_dir/Dockerfile"
python3 "$project_dir/gtk/generate-resource-overlay.py" \
    "$project_dir/openbox/theme" "$overlay_test_dir"
for control in minimize maximize restore close; do
    control_path="$overlay_test_dir/icons/16x16/status/window-${control}-symbolic.symbolic.png"
    test -s "$control_path"
    python3 -c \
        'import pathlib, sys; assert pathlib.Path(sys.argv[1]).read_bytes().startswith(b"\x89PNG\r\n\x1a\n")' \
        "$control_path"
done
grep -Fq '"system_theme": 1' \
    "$project_dir/Dockerfile"
grep -Fq 'popover.background.menu' \
    "$project_dir/gtk/PantalkGhost/gtk-3.0/gtk.css"
grep -Fq 'background-color: #020303;' \
    "$project_dir/gtk/PantalkGhost/gtk-3.0/gtk.css"
grep -Fq 'window.background.csd decoration' \
    "$project_dir/gtk/PantalkGhost/gtk-3.0/gtk.css"
grep -Fq 'decoration:not(:backdrop)' \
    "$project_dir/gtk/PantalkGhost/gtk-3.0/gtk.css"
grep -Fq 'headerbar.header-bar.titlebar' \
    "$project_dir/gtk/PantalkGhost/gtk-3.0/gtk.css"
grep -Fq 'border-radius: 0;' \
    "$project_dir/gtk/PantalkGhost/gtk-3.0/gtk.css"
grep -Fq 'padding-right: 4px;' \
    "$project_dir/gtk/PantalkGhost/gtk-3.0/gtk.css"
grep -Fq 'button.titlebutton:backdrop' \
    "$project_dir/gtk/PantalkGhost/gtk-3.0/gtk.css"
grep -Fq 'color: #dc143c;' \
    "$project_dir/gtk/PantalkGhost/gtk-3.0/gtk.css"
grep -Fxq 'gtk-font-name = Noto Sans 9' \
    "$project_dir/gtk/PantalkGhost/gtk-3.0/settings.ini"
test "$(grep -Fc '<name>Noto Sans</name>' "$project_dir/openbox/rc.xml")" -eq 6
test "$(grep -Fc '<size>9</size>' "$project_dir/openbox/rc.xml")" -eq 6
if grep -Fq '"BrowserThemeColor"' "$project_dir/Dockerfile"; then
    echo "BrowserThemeColor still overrides the GTK Chrome theme." >&2
    exit 1
fi
if grep -Fq -- '--pack-extension=' "$project_dir/Dockerfile"; then
    echo "The obsolete Chrome extension theme is still packaged." >&2
    exit 1
fi
grep -Fq "local neon_green='\\[\\e[38;5;46m\\]'" \
    "$project_dir/shell/bashrc"
grep -Fq 'PS1="${neon_green}@\\u ' "$project_dir/shell/bashrc"

# Terminals start in the workspace. Openbox chdirs to $HOME at startup whatever
# directory it was started from, so this cannot be set for the session and has
# to happen in the shell, which every terminal passes through. Both guards are
# load-bearing: without the PS1 test it would move non-interactive shells and
# break scripts that depend on their working directory, and without the $PWD
# test it would override a directory somebody chose on purpose.
grep -Fq 'cd /workspace' "$project_dir/shell/bashrc"
grep -Fq '[ -n "${PS1:-}" ]' "$project_dir/shell/bashrc"
grep -Fq '[ "$PWD" = "$HOME" ]' "$project_dir/shell/bashrc"
legacy_home="/home/ag""ent"
if rg --hidden --fixed-strings "$legacy_home" "$project_dir"; then
    echo "The former desktop home path is still present." >&2
    exit 1
fi

grep -Fq 'panel_items = PTSEC' "$project_dir/tint2/tint2rc"
grep -Fq 'execp_command = ghost-panel-status' \
    "$project_dir/tint2/tint2rc"

grep -Fq 'assets/favicon.svg' "$project_dir/kasm/patch.sh"
grep -Fq 'dynamic VNC desktop title was not removed' \
    "$project_dir/kasm/patch.sh"
grep -Fq 'COPY kasm/favicon.svg /usr/share/kasmvnc/www/assets/favicon.svg' \
    "$project_dir/Dockerfile"

# The mascot overlay is client-side only: it must be injected into the KasmVNC
# page and must never take pointer events away from the remote desktop.
grep -Fq 'assets/mascot.css' "$project_dir/kasm/patch.sh"
grep -Fq 'assets/mascot.js' "$project_dir/kasm/patch.sh"
grep -Fq 'the mascot overlay was not injected' "$project_dir/kasm/patch.sh"
# KasmVNC serves these assets with no cache-control, etag, or last-modified,
# so unversioned URLs leave browsers running a stale overlay against a freshly
# built image. The URLs must carry a content hash.
grep -Fq 'sha256sum "$WWW/assets/mascot.js"' "$project_dir/kasm/patch.sh"
grep -Fq 'mascot.css?v=${mascot_css_version}' "$project_dir/kasm/patch.sh"
grep -Fq 'mascot.js?v=${mascot_js_version}' "$project_dir/kasm/patch.sh"
grep -Fq 'COPY kasm/mascot.css /usr/share/kasmvnc/www/assets/mascot.css' \
    "$project_dir/Dockerfile"
grep -Fq 'COPY kasm/mascot.js /usr/share/kasmvnc/www/assets/mascot.js' \
    "$project_dir/Dockerfile"
# The ghost itself is the click target; the blurred glow around it must stay
# click-through so the dead zone over the desktop is no wider than the ghost.
grep -Fq 'pointer-events: auto;' "$project_dir/kasm/mascot.css"
grep -Fq 'pointer-events: none;' "$project_dir/kasm/mascot.css"
# Clicking synthesises the same key Openbox binds, rather than reaching into
# noVNC internals, so the two must stay in agreement.
grep -Fq "key(target, 'keydown', 'KeyG', 'g', true, true)" \
    "$project_dir/kasm/mascot.js"
grep -Fq '<keybind key="C-S-g">' "$project_dir/openbox/rc.xml"
# Every modifier the click presses must be released again, or the desktop is
# left treating later keystrokes as shortcuts.
grep -Fq "key(target, 'keyup', 'ShiftLeft', 'Shift', true, false)" \
    "$project_dir/kasm/mascot.js"
grep -Fq "key(target, 'keyup', 'ControlLeft', 'Control', false, false)" \
    "$project_dir/kasm/mascot.js"
# Only Control and Shift survive noVNC's Mac keyboard normalisation unchanged.
# Alt arrives as an AltGr-class modifier and Super arrives as Alt, so either
# one silently breaks the Openbox grab for Mac clients while still working on
# Linux - the exact failure that is invisible to testing from Linux.
# Matched in code form (quoted key names, "metaKey:") so the comments that
# explain why they are avoided do not trip the guard.
if grep -Fq "'AltLeft'" "$project_dir/kasm/mascot.js" ||
    grep -Fq "'AltRight'" "$project_dir/kasm/mascot.js" ||
    grep -Fq "'MetaLeft'" "$project_dir/kasm/mascot.js" ||
    grep -Fq 'metaKey:' "$project_dir/kasm/mascot.js" ||
    grep -Fq 'altKey:' "$project_dir/kasm/mascot.js"; then
    echo "The mascot shortcut uses a modifier noVNC rewrites for Mac clients." >&2
    exit 1
fi
# The Openbox binding must agree, for the same reason.
if grep -Eq '<keybind key="[^"]*[AW]-[^"]*g"' "$project_dir/openbox/rc.xml"; then
    echo "The harness binding uses Alt or Super, which Mac clients remap." >&2
    exit 1
fi
grep -Fq '<command>ghost-harness</command>' "$project_dir/openbox/rc.xml"
grep -Fq 'COPY shell/ghost-harness /usr/local/bin/ghost-harness' \
    "$project_dir/Dockerfile"
# The float keyframes must stay identical to .platform-float on the site.
grep -Fq 'translateY(-6px)' "$project_dir/kasm/mascot.css"
grep -Fq 'animation: pantalk_mascot_float 3s ease-in-out infinite;' \
    "$project_dir/kasm/mascot.css"
# The mascot is unframed: no card border or fill may creep back in.
if grep -Fq 'pantalk_mascot_card' "$project_dir/kasm/mascot.css" ||
    grep -Fq 'pantalk_mascot_card' "$project_dir/kasm/mascot.js"; then
    echo "The mascot is framed in a card again." >&2
    exit 1
fi

# The wallpaper and every window frame are near-black, so the focused window is
# outlined in white to make its edges findable. Unfocused frames must stay dark
# or the outline stops identifying which window is active.
themerc="$project_dir/openbox/theme/themerc"
grep -Fq 'window.active.border.color: #ffffff' "$themerc"
# No bottom handle: it drew a second line plus a boxed grip at each end. The
# resize paths that replace it must stay bound.
grep -Fq 'window.handle.width: 0' "$themerc"
# Client padding is the grab margin. With no handle and a 1px border, the frame
# offered 1px to grab at the bottom against a 28px titlebar; this widens the
# grabbable ring to 7px without widening the visible outline. Reading these back
# to 0 looks like tidying and silently makes the corners unusable again.
grep -Fq 'window.client.padding.width: 6' "$themerc"
grep -Fq 'window.client.padding.height: 6' "$themerc"
grep -Fq '<action name="Resize" />' "$project_dir/openbox/rc.xml"
if grep -Eq '^window\.inactive\.border\.color: *#(ffffff|FFFFFF)$' "$themerc"; then
    echo "Unfocused windows are outlined like the focused one." >&2
    exit 1
fi

grep -Fq \
    'COPY wallpaper/pantalk-ghost.svg /usr/share/backgrounds/pantalk-ghost.svg' \
    "$project_dir/Dockerfile"
grep -Fq 'wallpaper="/usr/share/backgrounds/pantalk-ghost.svg"' \
    "$project_dir/openbox/autostart"
grep -Fq '#24DBC9' "$project_dir/wallpaper/pantalk-ghost.svg"
if grep -Fq '<text' "$project_dir/wallpaper/pantalk-ghost.svg" ||
    grep -Fq 'M115.199 384V204.8' \
        "$project_dir/wallpaper/pantalk-ghost.svg"; then
    echo "The clean desktop wallpaper still contains logo artwork." >&2
    exit 1
fi
if grep -Fq 'simpledesktops.com' "$project_dir/Dockerfile" ||
    grep -Fq 'shuf -n 1' "$project_dir/openbox/autostart"; then
    echo "Random third-party wallpaper behavior is still present." >&2
    exit 1
fi

grep -Fq '/home/ghost/.kimi' "$project_dir/Dockerfile"
grep -Fq '$(VOLUME_PREFIX)-kimi:/home/ghost/.kimi' "$project_dir/Makefile"
grep -Fq 'ghost-kimi:/home/ghost/.kimi' \
    "$project_dir/deployments/ergo/compose.yaml"
grep -Fq 'ghost-kimi:/home/ghost/.kimi' \
    "$project_dir/deployments/mattermost/compose.yaml"
# The desktop harness and the chat-side agents must agree about the workspace:
# both work there unattended, so neither should sit on a trust prompt.
grep -Fq 'GHOST_TRUST_WORKSPACE' "$project_dir/init.sh"
# Codex's bubblewrap sandbox cannot create a user namespace in a container, so
# no sandbox mode is enforceable; the mode is declared so the config states what
# is true. It must be a top-level key - appended after the [projects."..."]
# tables it would silently become a per-project setting.
grep -Fq 'GHOST_CODEX_SANDBOX_MODE' "$project_dir/init.sh"
grep -Fq 'sandbox_mode = "%s"' "$project_dir/init.sh"
grep -Fq 'GHOST_CODEX_SANDBOX_MODE' "$project_dir/README.md"
grep -Fq 'trust_level = "trusted"' "$project_dir/init.sh"
grep -Fq 'hasTrustDialogAccepted' "$project_dir/init.sh"
grep -Fq 'GHOST_HARNESS_WORKDIR:-/workspace' "$project_dir/init.sh"
grep -Fq 'GHOST_HARNESS_WORKDIR:-/workspace' "$project_dir/shell/ghost-harness"

grep -Fq 'ownership-normalized' "$project_dir/init.sh"
grep -Fq 'W:/workspace' "$project_dir/init.sh"

panel_status="$project_dir/shell/ghost-panel-status"
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

# ghost-harness resolves the harness that agent-runtime-login recorded, and
# degrades predictably when nothing has been selected yet.
harness="$project_dir/shell/ghost-harness"
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
login="$project_dir/shell/agent-runtime-login"
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
