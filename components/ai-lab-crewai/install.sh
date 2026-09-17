#!/usr/bin/env bash
set -Eeuo pipefail

# CrewAI experimentation lab — its own venv and port, coexists with
# ai-lab-langchain / ai-lab-openai-sdk under the same shared 'ai-lab' user.

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
[[ "$target_root" == '/' ]] || { printf 'AI-lab (CrewAI) only supports --root /.\n' >&2; exit 64; }
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  printf 'Installing the AI lab requires root privileges.\n' >&2
  exit 77
fi
command -v jq >/dev/null 2>&1 || { printf 'jq is required for the AI-lab installer.\n' >&2; exit 69; }
jq -e 'type == "object" and .schema_version == 1 and .component == "ai-lab-crewai"' "$config" >/dev/null \
  || { printf 'AI-lab (CrewAI) config does not match schema version 1.\n' >&2; exit 65; }

if ! id ai-lab >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /home/ai-lab --shell /usr/sbin/nologin ai-lab
fi
if id -nG ai-lab 2>/dev/null | tr ' ' '\n' | grep -qx 'sudo'; then
  printf 'ai-lab user must not be a member of sudo.\n' >&2
  exit 78
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq python3-venv python3-pip

component_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
venv_dir=/home/ai-lab/crewai-env
if [[ ! -d "$venv_dir" ]]; then
  runuser -u ai-lab -- python3 -m venv "$venv_dir"
fi
runuser -u ai-lab -- "$venv_dir/bin/pip" install --no-cache-dir --quiet \
  crewai jupyterlab python-dotenv

install -d -m 0755 -o ai-lab -g ai-lab /home/ai-lab/notebooks
env_file=/home/ai-lab/.env
if [[ ! -f "$env_file" ]]; then
  cat > "$env_file" << 'ENVEOF'
# Add whichever model provider key you want the lab to use, then:
#   systemctl restart groomlake-ai-lab-crewai
# OPENAI_API_KEY=
# ANTHROPIC_API_KEY=
ENVEOF
  chown ai-lab:ai-lab "$env_file"
  chmod 0600 "$env_file"
fi

install -m 0644 "$component_dir/systemd/groomlake-ai-lab-crewai.service" \
  /etc/systemd/system/groomlake-ai-lab-crewai.service
systemctl daemon-reload
systemctl enable --now groomlake-ai-lab-crewai.service

state_dir="$target_root/var/lib/mission-systems-officer"
mkdir -p "$state_dir"
printf 'completed_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$state_dir/ai-lab-crewai.status"
chmod 0644 "$state_dir/ai-lab-crewai.status"
