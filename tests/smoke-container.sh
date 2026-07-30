#!/usr/bin/env bash

set -euo pipefail

container="${1:?usage: smoke-container.sh CONTAINER [ARCH]}"
expected_arch="${2:-}"
docker="${DOCKER:-docker}"

actual_arch="$("$docker" exec "$container" dpkg --print-architecture)"
if [ -n "$expected_arch" ] && [ "$actual_arch" != "$expected_arch" ]; then
    echo "Expected $expected_arch container, got $actual_arch" >&2
    exit 1
fi

"$docker" exec "$container" bash -ec '
    for command in agent-runtime-login desktop-panel-status desktop-harness \
        pantalk pantalkd \
        agent-browser copilot cbk codex claude kimi chromium; do
        command -v "$command" >/dev/null || {
            echo "[smoke] FAILED: $command is not on PATH" >&2
            exit 1
        }
    done

    case "$(dpkg --print-architecture)" in
        amd64)
            test -x /opt/google/chrome/google-chrome
            test ! -x /usr/bin/chromium
            ;;
        arm64)
            test -x /usr/bin/chromium
            test ! -x /opt/google/chrome/google-chrome
            ;;
        *)
            exit 1
            ;;
    esac

    chromium --version
    ! command -v ergo >/dev/null
    ! command -v halloy >/dev/null
    ! command -v halloy-node >/dev/null
    curl -fsS http://127.0.0.1:6901/ >/dev/null
'

# A version check only proves that the executable loader works. Launch the
# architecture's real headed browser on KasmVNC's display, find its visible
# window through X11, and capture the same framebuffer a remote user sees.
"$docker" exec --detach \
    --user agent \
    --env DISPLAY=:1 \
    --env HOME=/home/agent \
    "$container" \
    chromium file:///opt/browser/index.html

browser_ready=false
for attempt in $(seq 1 30); do
    if "$docker" exec \
        --user agent \
        --env DISPLAY=:1 \
        "$container" \
        xdotool search --onlyvisible --name 'Pantalk Ghost Browser' \
        >/dev/null 2>&1; then
        browser_ready=true
        break
    fi
    sleep 1
done

if [ "$browser_ready" != "true" ]; then
    echo "The $actual_arch browser did not create a visible desktop window." >&2
    "$docker" exec "$container" ps aux >&2 || true
    exit 1
fi

"$docker" exec \
    --user agent \
    --env DISPLAY=:1 \
    "$container" \
    scrot /tmp/ghost-browser-smoke.png
"$docker" exec "$container" test -s /tmp/ghost-browser-smoke.png
"$docker" exec "$container" rm -f /tmp/ghost-browser-smoke.png

echo "Ghost container and headed browser passed on linux/$actual_arch."
