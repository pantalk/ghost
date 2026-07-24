#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
deployment_dir="$(cd "$script_dir/.." && pwd)"
env_file="$deployment_dir/.env"
env_example="$deployment_dir/.env.example"
state_dir="$deployment_dir/.state"
pantalk_dir="$state_dir/pantalk"
template_file="$deployment_dir/config/pantalk.yaml.tmpl"
config_file="$pantalk_dir/config.yaml"

if [ ! -s "$env_file" ]; then
  install -m 0600 "$env_example" "$env_file"
  echo "Created $env_file"
fi

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

if [[ ! "${IRC_CHANNEL:-}" =~ ^[\#\&][A-Za-z0-9_.-]+$ ]]; then
  echo "IRC_CHANNEL must start with # or & and contain a valid channel name" >&2
  exit 1
fi

mkdir -p "$pantalk_dir"
chmod 700 "$state_dir" "$pantalk_dir"

temporary_file="${config_file}.tmp.$$"
sed "s|__IRC_CHANNEL__|$IRC_CHANNEL|g" \
  "$template_file" > "$temporary_file"
mv "$temporary_file" "$config_file"
chmod 600 "$config_file"
