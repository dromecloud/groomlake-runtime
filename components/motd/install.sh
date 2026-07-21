#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  printf 'Usage: %s --config <file> --root <absolute-path>\n' "$0" >&2
}

config=''
target_root='/'

while (( $# > 0 )); do
  case "$1" in
    --config)
      (( $# >= 2 )) || { usage; exit 64; }
      config=$2
      shift 2
      ;;
    --root)
      (( $# >= 2 )) || { usage; exit 64; }
      target_root=$2
      shift 2
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

[[ -n "$config" && -r "$config" ]] || { printf 'MOTD config is missing or unreadable.\n' >&2; exit 66; }
[[ "$target_root" == /* ]] || { printf 'Target root must be absolute.\n' >&2; exit 64; }

if [[ "$target_root" == '/' && ${EUID:-$(id -u)} -ne 0 ]]; then
  printf 'Installing into / requires root privileges.\n' >&2
  exit 77
fi

component_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
mkdir -p "$target_root/etc/groomlake" "$target_root/etc/update-motd.d"
install -m 0644 "$config" "$target_root/etc/groomlake/motd.txt"
install -m 0755 "$component_dir/render.sh" "$target_root/etc/update-motd.d/10-groomlake-profile"
