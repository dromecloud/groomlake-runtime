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
[[ "$target_root" == /* ]] || { printf 'Target root must be absolute.\n' >&2; exit 64; }
[[ "$target_root" == '/' ]] || { printf 'Hermes installs real system state and only supports --root /.\n' >&2; exit 64; }
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  printf 'Installing Hermes requires root privileges.\n' >&2
  exit 77
fi
command -v jq >/dev/null 2>&1 || { printf 'jq is required for the Hermes installer.\n' >&2; exit 69; }
jq -e '
  type == "object" and .schema_version == 1 and .component == "hermes" and
  (.installer_url | type == "string" and startswith("https://")) and
  (.installer_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
  (.apt_packages | type == "array" and length > 0 and all(.[]; type == "string")) and
  (.install_flags | type == "array" and all(.[]; type == "string"))
' "$config" >/dev/null || { printf 'Hermes config does not match schema version 1.\n' >&2; exit 65; }

installer_url=$(jq -r '.installer_url' "$config")
installer_sha256=$(jq -r '.installer_sha256' "$config")
mapfile -t apt_packages < <(jq -r '.apt_packages[]' "$config")
mapfile -t install_flags < <(jq -r '.install_flags[]' "$config")

# Dedicated, unprivileged runtime user. No sudo, no login shell — matches the
# Groomlake security boundary that Hermes must not run as root long-term.
if ! id hermes >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /home/hermes --shell /usr/sbin/nologin hermes
fi
if id -nG hermes 2>/dev/null | tr ' ' '\n' | grep -qx 'sudo'; then
  printf 'Hermes user must not be a member of sudo.\n' >&2
  exit 78
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq "${apt_packages[@]}"
# Fixes: "error while loading shared libraries: libatomic.so.1" observed on a
# fresh Ubuntu 24.04 server — libatomic1 must be present before Hermes' own
# installer runs, not discovered afterwards.
dpkg -s libatomic1 >/dev/null 2>&1 || { printf 'libatomic1 failed to install.\n' >&2; exit 70; }

installer_path=$(mktemp /tmp/hermes-install-XXXXXX.sh)
trap 'rm -f "$installer_path"' EXIT
curl -fsSL "$installer_url" -o "$installer_path"
downloaded_sha256=$(sha256sum "$installer_path" | awk '{print $1}')
[[ "$downloaded_sha256" == "$installer_sha256" ]] \
  || { printf 'Hermes installer checksum mismatch: expected=%s actual=%s\n' "$installer_sha256" "$downloaded_sha256" >&2; exit 79; }
chmod 0500 "$installer_path"
chown hermes:hermes "$installer_path"

# Run the verified installer as the unprivileged hermes user. --skip-setup and
# --non-interactive avoid the interactive API-key/gateway wizard: model access
# is deliberately configured later, by a human, never baked into the manifest.
runuser -u hermes -- env HOME=/home/hermes bash "$installer_path" "${install_flags[@]}"
