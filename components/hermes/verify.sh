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

hermes_shell=$(getent passwd hermes | cut -d: -f7)
[[ "$hermes_shell" != */nologin ]] || { printf 'Hermes user has no login shell (SSH access would be refused).\n' >&2; exit 1; }
[[ -f /home/hermes/.ssh/authorized_keys ]] || { printf 'Hermes has no authorized_keys — direct SSH login is not possible.\n' >&2; exit 1; }
key_perm=$(stat -c '%a' /home/hermes/.ssh/authorized_keys 2>/dev/null || stat -f '%Lp' /home/hermes/.ssh/authorized_keys)
[[ "$key_perm" == '600' ]] || { printf 'Hermes authorized_keys has unsafe permissions: %s\n' "$key_perm" >&2; exit 1; }
grep -q '/home/hermes/.local/bin' /etc/environment 2>/dev/null \
  || { printf 'Hermes PATH is not set in /etc/environment (non-interactive SSH commands will not find hermes).\n' >&2; exit 1; }
[[ -x /home/hermes/.local/bin/hermes-launcher ]] \
  || { printf 'hermes-launcher shim is missing (Hermes Desktop SSH connect mode will fail to locate hermes).\n' >&2; exit 1; }

command_path="/home/hermes/.local/bin/hermes"
[[ -x "$command_path" ]] || { printf 'Hermes command is missing or not executable: %s\n' "$command_path" >&2; exit 1; }
owner=$(stat -c '%U' "$command_path" 2>/dev/null || stat -f '%Su' "$command_path")
[[ "$owner" == 'hermes' ]] || { printf 'Hermes command is not owned by the hermes user.\n' >&2; exit 1; }

runuser -u hermes -- env HOME=/home/hermes "$command_path" --version >/dev/null \
  || { printf 'Hermes command failed to run as the hermes user.\n' >&2; exit 1; }

# Optional: only verified when the owner actually requested automatic model
# access (MSO_NOUS_API_KEY inherited from the same shell environment that
# ran install.sh -- see install.sh for the full mechanism). Absent by
# default, which is the expected/normal case.
if [[ -n "${MSO_NOUS_API_KEY:-}" ]]; then
  env_file=/home/hermes/.hermes/.env
  [[ -f "$env_file" ]] || { printf 'MSO_NOUS_API_KEY was requested but %s is missing.\n' "$env_file" >&2; exit 1; }
  env_perm=$(stat -c '%a' "$env_file" 2>/dev/null || stat -f '%Lp' "$env_file")
  [[ "$env_perm" == '600' ]] || { printf '%s has unsafe permissions: %s\n' "$env_file" "$env_perm" >&2; exit 1; }
  grep -q "^NOUS_API_KEY=${MSO_NOUS_API_KEY}\$" "$env_file" \
    || { printf 'NOUS_API_KEY in %s does not match the requested key.\n' "$env_file" >&2; exit 1; }
fi
