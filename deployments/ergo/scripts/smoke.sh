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

ghost_pantalk() {
  compose exec \
    -T \
    --user ghost \
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

wait_for_url "The Lounge" \
  "http://127.0.0.1:${THELOUNGE_PORT:-9000}/"
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
    echo "Pantalk did not report the $bot IRC bot" >&2
    exit 1
  fi
done

observer_output="$(mktemp)"
# shellcheck disable=SC2329
cleanup() {
  rm -f "$observer_output"
}
trap cleanup EXIT

outbound_marker="pantalk-ghost-outbound-$(date +%s)-$$"
(
  {
    printf 'NICK observer\r\n'
    printf 'USER observer 0 * :Pantalk Smoke Observer\r\n'
    printf 'JOIN %s\r\n' "$IRC_CHANNEL"
    sleep 2
    sleep 5
    printf 'QUIT :smoke complete\r\n'
  } |
    compose exec -T ergo nc -w 10 127.0.0.1 6667
) > "$observer_output" &
observer_pid=$!

sleep 3
ghost_pantalk send \
  --bot codex \
  --channel "$IRC_CHANNEL" \
  --text "$outbound_marker" >/dev/null
wait "$observer_pid"

if ! grep -Fq "$outbound_marker" "$observer_output"; then
  echo "The IRC observer did not receive the Pantalk outbound message" >&2
  exit 1
fi

inbound_marker="pantalk-ghost-inbound-$(date +%s)-$$"
{
  printf 'NICK sender\r\n'
  printf 'USER sender 0 * :Pantalk Smoke Sender\r\n'
  printf 'JOIN %s\r\n' "$IRC_CHANNEL"
  printf 'PRIVMSG %s :%s\r\n' "$IRC_CHANNEL" "$inbound_marker"
  printf 'QUIT :smoke complete\r\n'
} |
  compose exec -T ergo nc -w 5 127.0.0.1 6667 >/dev/null

for attempt in $(seq 1 30); do
  history="$(
    ghost_pantalk history \
      --bot codex \
      --search "$inbound_marker" \
      --json
  )"
  if grep -Fq "$inbound_marker" <<< "$history"; then
    echo "Ergo, The Lounge, and Ghost passed the IRC smoke test"
    exit 0
  fi
  sleep 1
done

echo "Pantalk did not receive the IRC smoke message" >&2
exit 1
