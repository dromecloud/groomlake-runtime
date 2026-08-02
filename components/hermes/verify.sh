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
[[ -r "$config" ]] || { printf 'Hermes config is missing or unreadable.\n' >&2; exit 66; }
[[ "$target_root" == '/' ]] || { printf 'Hermes verification only supports --root /.\n' >&2; exit 64; }

id hermes >/dev/null 2>&1 || { printf 'Hermes system user is missing.\n' >&2; exit 1; }
if id -nG hermes 2>/dev/null | tr ' ' '\n' | grep -qx 'sudo'; then
  printf 'Hermes user must not be a member of sudo.\n' >&2
  exit 1
fi
dpkg -s libatomic1 >/dev/null 2>&1 || { printf 'libatomic1 is not installed.\n' >&2; exit 1; }

command_path="/home/hermes/.local/bin/hermes"
[[ -x "$command_path" ]] || { printf 'Hermes command is missing or not executable: %s\n' "$command_path" >&2; exit 1; }
owner=$(stat -c '%U' "$command_path" 2>/dev/null || stat -f '%Su' "$command_path")
[[ "$owner" == 'hermes' ]] || { printf 'Hermes command is not owned by the hermes user.\n' >&2; exit 1; }

runuser -u hermes -- env HOME=/home/hermes "$command_path" --version >/dev/null \
  || { printf 'Hermes command failed to run as the hermes user.\n' >&2; exit 1; }
