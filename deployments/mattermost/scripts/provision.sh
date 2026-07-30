#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
deployment_dir="$(cd "$script_dir/.." && pwd)"
compose_file="$deployment_dir/compose.yaml"
env_file="$deployment_dir/.env"
state_dir="$deployment_dir/.state"
token_dir="$state_dir/tokens"
pantalk_dir="$state_dir/pantalk"
template_file="$deployment_dir/config/pantalk.yaml.tmpl"

if [ ! -s "$env_file" ]; then
  echo "Missing $env_file. Run make prepare first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

required_variables=(
  MATTERMOST_ADMIN_USERNAME
  MATTERMOST_ADMIN_EMAIL
  MATTERMOST_ADMIN_PASSWORD
  MATTERMOST_TEAM
  MATTERMOST_CHANNEL
  MATTERMOST_PORT
)

for variable in "${required_variables[@]}"; do
  if [ -z "${!variable:-}" ]; then
    echo "$variable must be set in $env_file" >&2
    exit 1
  fi
done

for value in "$MATTERMOST_ADMIN_USERNAME" "$MATTERMOST_TEAM" "$MATTERMOST_CHANNEL"; do
  if [[ ! "$value" =~ ^[a-z][a-z0-9_-]{2,21}$ ]]; then
    echo "Mattermost names must start with a letter and contain 3-22 lowercase letters, numbers, underscores, or hyphens: $value" >&2
    exit 1
  fi
done

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose is required as the docker compose plugin" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 1
fi

compose() {
  docker compose --env-file "$env_file" -f "$compose_file" "$@"
}

mmctl_local() {
  compose exec -T mattermost /mattermost/bin/mmctl "$@" --local
}

mmctl_remote() {
  compose exec -T mattermost /mattermost/bin/mmctl "$@"
}

wait_for_mattermost() {
  echo "Waiting for Mattermost"
  for attempt in $(seq 1 120); do
    if mmctl_local system status >/dev/null 2>&1; then
      return
    fi
    if [ "$attempt" -eq 120 ]; then
      echo "Mattermost did not become ready within 120 seconds" >&2
      compose logs --tail 100 mattermost >&2 || true
      exit 1
    fi
    sleep 1
  done
}

json_has_name() {
  local kind="$1"
  local name="$2"
  grep -Fq "\"$kind\": \"$name\""
}

extract_token() {
  awk -F '"' '/"token":/ { print $4; exit }'
}

write_secret() {
  local path="$1"
  local value="$2"
  local temporary_file="${path}.tmp.$$"

  umask 077
  printf '%s\n' "$value" > "$temporary_file"
  mv "$temporary_file" "$path"
  chmod 600 "$path"
}

token_is_valid() {
  local token="$1"
  curl \
    --fail \
    --silent \
    --output /dev/null \
    --header "Authorization: Bearer $token" \
    "http://127.0.0.1:${MATTERMOST_PORT}/api/v4/users/me"
}

ensure_bot_token() {
  local username="$1"
  local display_name="$2"
  local token_file="$token_dir/$username"
  local output
  local token=""

  if [ -s "$token_file" ]; then
    token="$(tr -d '\r\n' < "$token_file")"
    if token_is_valid "$token"; then
      printf '%s' "$token"
      return
    fi
  fi

  if mmctl_remote bot list --json 2>/dev/null |
    json_has_name username "$username"; then
    output="$(mmctl_remote token generate "$username" pantalk-ghost --json)"
  else
    output="$(
      mmctl_remote bot create "$username" \
        --display-name "$display_name" \
        --description "Managed by Pantalk Ghost" \
        --with-token \
        --json
    )"
  fi

  token="$(printf '%s\n' "$output" | extract_token)"
  if [ -z "$token" ]; then
    echo "Mattermost did not return an access token for $username" >&2
    exit 1
  fi

  write_secret "$token_file" "$token"
  printf '%s' "$token"
}

render_pantalk_config() {
  local codex_token="$1"
  local claude_token="$2"
  local output_file="$pantalk_dir/config.yaml"
  local temporary_file="${output_file}.tmp.$$"

  sed \
    -e "s|__CODEX_TOKEN__|$codex_token|g" \
    -e "s|__CLAUDE_TOKEN__|$claude_token|g" \
    -e "s|__MATTERMOST_CHANNEL__|$MATTERMOST_CHANNEL|g" \
    "$template_file" > "$temporary_file"

  mv "$temporary_file" "$output_file"
  chmod 600 "$output_file"
}

mkdir -p "$token_dir" "$pantalk_dir"
chmod 700 "$state_dir" "$token_dir" "$pantalk_dir"

wait_for_mattermost

if mmctl_local user search "$MATTERMOST_ADMIN_USERNAME" --json 2>/dev/null |
  json_has_name username "$MATTERMOST_ADMIN_USERNAME"; then
  mmctl_local user change-password "$MATTERMOST_ADMIN_USERNAME" \
    --password "$MATTERMOST_ADMIN_PASSWORD" >/dev/null
else
  mmctl_local user create \
    --email "$MATTERMOST_ADMIN_EMAIL" \
    --username "$MATTERMOST_ADMIN_USERNAME" \
    --password "$MATTERMOST_ADMIN_PASSWORD" \
    --system-admin \
    --email-verified \
    --disable-welcome-email >/dev/null
fi

mmctl_remote auth clean >/dev/null 2>&1 || true
mmctl_remote auth login http://localhost:8065 \
  --name provisioning \
  --username "$MATTERMOST_ADMIN_USERNAME" \
  --password-file /run/pantalk-secrets/mattermost-admin-password >/dev/null

cleanup_auth() {
  mmctl_remote auth clean >/dev/null 2>&1 || true
}
trap cleanup_auth EXIT

if ! mmctl_remote team search "$MATTERMOST_TEAM" --json 2>/dev/null |
  json_has_name name "$MATTERMOST_TEAM"; then
  mmctl_remote team create \
    --name "$MATTERMOST_TEAM" \
    --display-name "Pantalk" >/dev/null
fi

if ! mmctl_remote channel search "$MATTERMOST_CHANNEL" \
  --team "$MATTERMOST_TEAM" \
  --json 2>/dev/null |
  json_has_name name "$MATTERMOST_CHANNEL"; then
  mmctl_remote channel create \
    --team "$MATTERMOST_TEAM" \
    --name "$MATTERMOST_CHANNEL" \
    --display-name "Agents" \
    --purpose "Work with Pantalk agents" >/dev/null
fi

codex_token="$(ensure_bot_token codex "Codex Agent")"
claude_token="$(ensure_bot_token claude "Claude Agent")"

mmctl_remote team users add \
  "$MATTERMOST_TEAM" \
  "$MATTERMOST_ADMIN_USERNAME" \
  codex \
  claude >/dev/null

mmctl_remote channel users add \
  "$MATTERMOST_TEAM:$MATTERMOST_CHANNEL" \
  "$MATTERMOST_ADMIN_USERNAME" \
  codex \
  claude >/dev/null

render_pantalk_config "$codex_token" "$claude_token"

if [ -n "$(compose ps --status running --quiet ghost 2>/dev/null)" ]; then
  compose exec \
    -T \
    --user agent \
    --env XDG_RUNTIME_DIR=/run/user/1000 \
    ghost \
    pantalk reload >/dev/null
fi

echo "Mattermost provisioning is complete"
