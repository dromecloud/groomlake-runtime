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
[[ -r "$config" ]] || { printf 'AI-lab (CrewAI) config is missing or unreadable.\n' >&2; exit 66; }
[[ "$target_root" == '/' ]] || { printf 'AI-lab (CrewAI) verification only supports --root /.\n' >&2; exit 64; }

id ai-lab >/dev/null 2>&1 || { printf 'ai-lab system user is missing.\n' >&2; exit 1; }
if id -nG ai-lab 2>/dev/null | tr ' ' '\n' | grep -qx 'sudo'; then
  printf 'ai-lab user must not be a member of sudo.\n' >&2
  exit 1
fi

venv_python=/home/ai-lab/crewai-env/bin/python
[[ -x "$venv_python" ]] || { printf 'CrewAI venv is missing: %s\n' "$venv_python" >&2; exit 1; }
# MSR runs components from its own caller's working directory, which may be
# unreadable for ai-lab (/root, for example). CrewAI auto-loads a .env from the
# working directory on import and then dies with PermissionError, so pin a
# directory ai-lab can actually read.
runuser -u ai-lab -- env -C /home/ai-lab HOME=/home/ai-lab "$venv_python" -c 'import crewai, jupyterlab' \
  || { printf 'CrewAI venv is missing required packages.\n' >&2; exit 1; }

status_file="$target_root/var/lib/mission-systems-officer/ai-lab-crewai.status"
[[ -f "$status_file" ]] || { printf 'AI-lab (CrewAI) status marker is missing.\n' >&2; exit 1; }
grep -q '^completed_at=' "$status_file" || { printf 'AI-lab (CrewAI) status marker is malformed.\n' >&2; exit 1; }

systemctl is-active --quiet groomlake-ai-lab-crewai.service \
  || { printf 'groomlake-ai-lab-crewai.service is not active.\n' >&2; exit 1; }
