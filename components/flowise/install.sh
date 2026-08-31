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
[[ "$target_root" == /* ]] || { printf 'Target root must be absolute.\n' >&2; exit 64; }
[[ "$target_root" == '/' ]] || { printf 'Flowise installs real system state and only supports --root /.\n' >&2; exit 64; }
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  printf 'Installing Flowise requires root privileges.\n' >&2
  exit 77
fi
command -v jq >/dev/null 2>&1 || { printf 'jq is required for the Flowise installer.\n' >&2; exit 69; }

jq -e '
  type == "object" and .schema_version == 1 and .component == "flowise" and
  (.image | type == "string" and test("^flowiseai/flowise:[0-9]+\\.[0-9]+\\.[0-9]+$")) and
  (.port | type == "number") and
  (.apt_packages | type == "array" and length > 0 and all(.[]; type == "string"))
' "$config" >/dev/null || { printf 'Flowise config does not match schema version 1.\n' >&2; exit 65; }

# Image tag is pinned and validated against the ^flowiseai/flowise:X.Y.Z$
# pattern above, deliberately rejecting ":latest" -- see the 3.1.4 startup
# crash (this.db.exec is not a function / connect-sqlite3) discovered
# during manual testing on ironbird-test-phase4. Only an explicit,
# reviewed config change can move the pinned version forward.
image=$(jq -r '.image' "$config")
port=$(jq -r '.port' "$config")
mapfile -t apt_packages < <(jq -r '.apt_packages[]' "$config")

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq "${apt_packages[@]}"

if ! docker compose version >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-compose-plugin
fi

install -d -m 0755 /opt/flowise/data

cat > /opt/flowise/docker-compose.yml << COMPOSE
services:
  flowise:
    image: ${image}
    container_name: flowise
    restart: unless-stopped
    ports:
      - "127.0.0.1:${port}:${port}"
    environment:
      - PORT=${port}
    volumes:
      - /opt/flowise/data:/root/.flowise
COMPOSE

cd /opt/flowise
docker compose up -d
