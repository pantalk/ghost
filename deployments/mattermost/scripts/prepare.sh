#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
deployment_dir="$(cd "$script_dir/.." && pwd)"
env_file="$deployment_dir/.env"
secret_dir="$deployment_dir/.state/secrets"
admin_password_file="$secret_dir/mattermost-admin-password"

if [ ! -s "$env_file" ]; then
  if ! command -v openssl >/dev/null 2>&1; then
    echo "openssl is required to generate deployment credentials" >&2
    exit 1
  fi

  umask 077
  postgres_password="Pantalk-1-$(openssl rand -hex 24)"
  admin_password="Pantalk-1-$(openssl rand -hex 24)"
  temporary_file="${env_file}.tmp.$$"

  cat > "$temporary_file" <<EOF
POSTGRES_IMAGE=postgres:18.2-alpine
MATTERMOST_IMAGE=mattermost/mattermost-team-edition:11.7.0
GHOST_IMAGE=ghcr.io/pantalk/ghost:0.0.8

PANTALK_VERSION=0.0.12

MATTERMOST_BIND_ADDRESS=127.0.0.1
MATTERMOST_PORT=8065
MATTERMOST_SITE_URL=http://127.0.0.1:8065
GHOST_BIND_ADDRESS=127.0.0.1
GHOST_PORT=6902
GHOST_RESOLUTION=1920x1080

MATTERMOST_ADMIN_USERNAME=operator
MATTERMOST_ADMIN_EMAIL=operator@pantalk.local
MATTERMOST_ADMIN_PASSWORD=$admin_password
MATTERMOST_TEAM=pantalk
MATTERMOST_CHANNEL=agents

POSTGRES_USER=mmuser
POSTGRES_PASSWORD=$postgres_password
POSTGRES_DB=mattermost
EOF

  mv "$temporary_file" "$env_file"
  chmod 600 "$env_file"

  echo "Created $env_file with generated local credentials"
fi

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

if [ -z "${MATTERMOST_ADMIN_PASSWORD:-}" ]; then
  echo "MATTERMOST_ADMIN_PASSWORD must be set in $env_file" >&2
  exit 1
fi

# The parent .state directory is private. The mounted secrets directory and
# password file must be readable by Mattermost's unprivileged container user.
mkdir -p "$deployment_dir/.state"
chmod 700 "$deployment_dir/.state"
mkdir -p "$secret_dir"
chmod 755 "$secret_dir"
printf '%s\n' "$MATTERMOST_ADMIN_PASSWORD" > "$admin_password_file"
chmod 644 "$admin_password_file"
