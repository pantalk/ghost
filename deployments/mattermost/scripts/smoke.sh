#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
deployment_dir="$(cd "$script_dir/.." && pwd)"
compose_file="$deployment_dir/compose.yaml"
env_file="$deployment_dir/.env"

if [ ! -s "$env_file" ]; then
  echo "Missing $env_file. Run make up first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

compose() {
  docker compose --env-file "$env_file" -f "$compose_file" "$@"
}

mmctl_remote() {
  compose exec -T mattermost /mattermost/bin/mmctl "$@"
}

ghost_pantalk() {
  compose exec \
    -T \
    --user agent \
    --env XDG_RUNTIME_DIR=/run/user/1000 \
    ghost \
    pantalk "$@"
}

wait_for_url() {
  local name="$1"
  local url="$2"

  for attempt in $(seq 1 60); do
    if curl --fail --silent "$url" >/dev/null; then
      return
    fi
    sleep 2
  done

  echo "$name did not become ready at $url" >&2
  exit 1
}

wait_for_url Mattermost \
  "http://127.0.0.1:${MATTERMOST_PORT:-8065}/api/v4/system/ping"
wait_for_url Ghost \
  "http://127.0.0.1:${GHOST_PORT:-6902}/index.html"

for attempt in $(seq 1 60); do
  if ghost_pantalk ping >/dev/null 2>&1; then
    break
  fi
  if [ "$attempt" -eq 60 ]; then
    echo "Pantalk did not become ready inside Ghost" >&2
    compose logs --tail 100 ghost >&2 || true
    exit 1
  fi
  sleep 2
done

bots="$(ghost_pantalk bots --json)"
for bot in codex claude; do
  if ! grep -Fq "\"name\":\"$bot\"" <<< "$bots" &&
    ! grep -Fq "\"name\": \"$bot\"" <<< "$bots"; then
    echo "Pantalk did not report the $bot Mattermost bot" >&2
    exit 1
  fi
done

mmctl_remote auth clean >/dev/null 2>&1 || true
mmctl_remote auth login http://localhost:8065 \
  --name smoke \
  --username "$MATTERMOST_ADMIN_USERNAME" \
  --password-file /run/pantalk-secrets/mattermost-admin-password >/dev/null

# shellcheck disable=SC2329
cleanup_auth() {
  mmctl_remote auth clean >/dev/null 2>&1 || true
}
trap cleanup_auth EXIT

channel_json="$(
  mmctl_remote channel search "$MATTERMOST_CHANNEL" \
    --team "$MATTERMOST_TEAM" \
    --json
)"
channel_id="$(
  printf '%s\n' "$channel_json" |
    awk -F '"' '/"id":/ { print $4; exit }'
)"

if [ -z "$channel_id" ]; then
  echo "Could not resolve the Mattermost channel ID" >&2
  exit 1
fi

outbound_marker="pantalk-ghost-outbound-$(date +%s)-$$"
ghost_pantalk send \
  --bot codex \
  --channel "$channel_id" \
  --text "$outbound_marker" >/dev/null

inbound_marker="pantalk-ghost-inbound-$(date +%s)-$$"
mmctl_remote post create "$MATTERMOST_TEAM:$MATTERMOST_CHANNEL" \
  --message "$inbound_marker" >/dev/null

for attempt in $(seq 1 30); do
  history="$(
    ghost_pantalk history \
      --bot codex \
      --search "$inbound_marker" \
      --json
  )"
  if grep -Fq "$inbound_marker" <<< "$history"; then
    echo "Mattermost and Ghost passed the messaging smoke test"
    exit 0
  fi
  sleep 1
done

echo "Pantalk did not receive the Mattermost smoke message" >&2
exit 1
