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
env_file="$target_root/etc/groomlake/health.env"
reporter="$target_root/usr/local/libexec/groomlake-acars-health-report"
[[ -f "$env_file" ]] || { printf 'Health environment file is missing.\n' >&2; exit 1; }
[[ "$(stat -c '%a' "$env_file" 2>/dev/null || stat -f '%Lp' "$env_file")" == 600 ]] \
  || { printf 'Health environment file must be mode 0600.\n' >&2; exit 1; }
[[ -x "$reporter" ]] || { printf 'Health reporter is missing or not executable.\n' >&2; exit 1; }
[[ -f "$target_root/etc/systemd/system/groomlake-acars-health.service" ]] \
  || { printf 'Health service unit is missing.\n' >&2; exit 1; }
[[ -f "$target_root/etc/systemd/system/groomlake-acars-health.timer" ]] \
  || { printf 'Health timer unit is missing.\n' >&2; exit 1; }
