#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
web_env="${LANTAW_WEB_ENV:-$project_dir/.env}"

if [[ ! -f "$web_env" ]]; then
  echo "Could not find the Lantaw web environment at: $web_env" >&2
  exit 1
fi

tmdb_token="$(sed -n 's/^TMDB_V4_TOKEN=//p' "$web_env" | head -n 1)"
if [[ -z "$tmdb_token" ]]; then
  echo "TMDB_V4_TOKEN is missing from: $web_env" >&2
  exit 1
fi

cd "$project_dir"
exec flutter run --dart-define="TMDB_V4_TOKEN=$tmdb_token" "$@"
