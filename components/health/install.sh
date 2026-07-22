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

[[ -r "$config" ]] || { printf 'Health config is missing or unreadable.\n' >&2; exit 66; }
[[ "$target_root" == /* ]] || { printf 'Target root must be absolute.\n' >&2; exit 64; }
if [[ "$target_root" == '/' && ${EUID:-$(id -u)} -ne 0 ]]; then
  printf 'Installing health reporter into / requires root privileges.\n' >&2
  exit 77
fi
command -v jq >/dev/null 2>&1 || { printf 'jq is required for the health reporter.\n' >&2; exit 69; }
jq -e 'type == "object" and .schema_version == 1 and .reporter == "acars"' "$config" >/dev/null \
  || { printf 'Health config does not match schema version 1.\n' >&2; exit 65; }

health_url=${MSO_HEALTH_URL:-}
health_token=${MSO_HEALTH_TOKEN:-}
server_name=${MSO_SERVER_NAME:-}
profile=${MSO_PROFILE:-}
bootstrap_version=${MSO_BOOTSTRAP_VERSION:-unknown}
[[ "$health_url" == https://toolhub.horizon-hub.one/assets/groomlake-health.php ]] \
  || { printf 'Health URL is not the approved HTTPS endpoint.\n' >&2; exit 78; }
[[ "$health_token" =~ ^[0-9a-f]{64}$ ]] || { printf 'Health token is missing or malformed.\n' >&2; exit 78; }
[[ "$server_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || { printf 'Server name is missing or malformed.\n' >&2; exit 78; }
[[ "$profile" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] || { printf 'MSO profile is missing or malformed.\n' >&2; exit 78; }

component_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
etc_dir="$target_root/etc/groomlake"
state_dir="$target_root/var/lib/mission-systems-officer"
mkdir -p "$etc_dir" "$state_dir" "$target_root/usr/local/libexec" "$target_root/etc/systemd/system"

health_env="$etc_dir/health.env"
{
  printf 'MSO_HEALTH_URL=%q\n' "$health_url"
  printf 'MSO_HEALTH_TOKEN=%q\n' "$health_token"
  printf 'MSO_SERVER_NAME=%q\n' "$server_name"
  printf 'MSO_PROFILE=%q\n' "$profile"
  printf 'MSO_BOOTSTRAP_VERSION=%q\n' "$bootstrap_version"
} > "$health_env"
chmod 0600 "$health_env"
install -m 0700 "$component_dir/report.sh" "$target_root/usr/local/libexec/groomlake-acars-health-report"
install -m 0644 "$component_dir/systemd/groomlake-acars-health.service" "$target_root/etc/systemd/system/groomlake-acars-health.service"
install -m 0644 "$component_dir/systemd/groomlake-acars-health.timer" "$target_root/etc/systemd/system/groomlake-acars-health.timer"

if [[ "$target_root" == '/' ]] && command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload
  systemctl enable --now groomlake-acars-health.timer
fi
