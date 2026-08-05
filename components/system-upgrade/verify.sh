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
[[ -r "$config" ]] || { printf 'System-upgrade config is missing or unreadable.\n' >&2; exit 66; }
[[ "$target_root" == '/' ]] || { printf 'System-upgrade verification only supports --root /.\n' >&2; exit 64; }

status_file="$target_root/var/lib/mission-systems-officer/system-upgrade.status"
[[ -f "$status_file" ]] || { printf 'System-upgrade status marker is missing.\n' >&2; exit 1; }
grep -q '^completed_at=' "$status_file" || { printf 'System-upgrade status marker is malformed.\n' >&2; exit 1; }

if command -v dpkg >/dev/null 2>&1; then
  broken=$(dpkg --audit 2>/dev/null)
  [[ -z "$broken" ]] || { printf 'dpkg --audit reports broken packages after upgrade:\n%s\n' "$broken" >&2; exit 1; }
fi
