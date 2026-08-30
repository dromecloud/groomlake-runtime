#!/usr/bin/env bash
set -Eeuo pipefail

usage() { printf 'Usage: %s --config <file> --root <absolute-path>\n' "$0" >&2; }
config=''
target_root='/'
while (( $# > 0 )); do
  case "$1" in
    --config) (( $# >= 2 )) || { usage; exit 64; }; config=$2; shift 2 ;;
    --root) (( $# >= 2 )) || { usage; exit 64; }; target_root=$2; shift 2 ;;
    *) usage; exit 64 ;;
  esac
done
[[ -r "$config" ]] || { printf 'Flowise config is missing or unreadable.\n' >&2; exit 66; }
[[ "$target_root" == '/' ]] || { printf 'Flowise verification only supports --root /.\n' >&2; exit 64; }
command -v jq >/dev/null 2>&1 || { printf 'jq is required for the Flowise verifier.\n' >&2; exit 69; }

port=$(jq -r '.port' "$config")
image=$(jq -r '.image' "$config")

[[ -f /opt/flowise/docker-compose.yml ]] || { printf 'Flowise compose file is missing: /opt/flowise/docker-compose.yml\n' >&2; exit 1; }

running_image=$(docker inspect --format '{{.Config.Image}}' flowise 2>/dev/null || true)
[[ -n "$running_image" ]] || { printf 'Flowise container is not present.\n' >&2; exit 1; }
[[ "$running_image" == "$image" ]] \
  || { printf 'Flowise container image mismatch: expected=%s actual=%s\n' "$image" "$running_image" >&2; exit 1; }

container_status=$(docker inspect --format '{{.State.Status}}' flowise 2>/dev/null || true)
[[ "$container_status" == 'running' ]] \
  || { printf 'Flowise container is not running (status: %s).\n' "$container_status" >&2; exit 1; }

for i in $(seq 1 10); do
  if curl -sf -o /dev/null "http://127.0.0.1:${port}"; then
    printf 'Flowise reachable on port %s\n' "$port"
    exit 0
  fi
  sleep 3
done

printf 'Flowise not reachable on port %s after waiting\n' "$port" >&2
exit 1
