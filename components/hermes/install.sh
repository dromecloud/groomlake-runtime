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

# Dedicated, unprivileged runtime user. No sudo — that's the actual Groomlake
# security boundary (Hermes must never run as root/with elevated rights).
# The shell IS a real login shell (/bin/bash, not nologin): remote tooling
# (Hermes Desktop's SSH connect mode, or an operator) needs to reach this
# user directly over SSH instead of going through root + runuser. That does
# not widen access — whoever already holds the trusted key can reach hermes
# via root+runuser anyway; this just lets them do it directly.
if ! id hermes >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /home/hermes --shell /bin/bash hermes
else
  chsh -s /bin/bash hermes
fi
if id -nG hermes 2>/dev/null | tr ' ' '\n' | grep -qx 'sudo'; then
  printf 'Hermes user must not be a member of sudo.\n' >&2
  exit 78
fi

# Mirror root's trusted keys onto hermes so the same platform key that
# provisions the server can also log in directly as the restricted user.
if [[ -f /root/.ssh/authorized_keys ]]; then
  install -d -m 0700 -o hermes -g hermes /home/hermes/.ssh
  install -m 0600 -o hermes -g hermes /root/.ssh/authorized_keys /home/hermes/.ssh/authorized_keys
fi

# `ssh hermes@host "hermes ..."` runs a non-interactive, non-login shell that
# reads neither ~/.bashrc nor ~/.profile, so a PATH set only there is
# invisible to that invocation. /etc/environment is read by pam_env for every
# SSH session regardless of shell mode, so this is the one place a fix here
# is guaranteed to apply.
if ! grep -q '/home/hermes/.local/bin' /etc/environment 2>/dev/null; then
  sed -i 's#^PATH="#PATH="/home/hermes/.local/bin:#' /etc/environment
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

# Workaround for a Hermes Desktop bug: its SSH connect mode resolves a
# `exec <python> <script> "$@"` wrapper by taking only the first exec
# argument (the interpreter), dropping the script path, and ends up trying
# to run the bare python binary as "hermes". A one-hop indirection shim
# (single-argument exec, no script path) resolves correctly instead.
cat > /home/hermes/.local/bin/hermes-launcher << 'LAUNCHER'
#!/usr/bin/env bash
exec /home/hermes/.local/bin/hermes "$@"
LAUNCHER
chmod 0755 /home/hermes/.local/bin/hermes-launcher
chown hermes:hermes /home/hermes/.local/bin/hermes-launcher
