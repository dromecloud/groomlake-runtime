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

installed_config="$target_root/etc/groomlake/motd.txt"
renderer="$target_root/etc/update-motd.d/10-groomlake-profile"

[[ -f "$installed_config" ]] || { printf 'Installed MOTD config is missing.\n' >&2; exit 1; }
[[ -x "$renderer" ]] || { printf 'Installed MOTD renderer is missing or not executable.\n' >&2; exit 1; }
cmp -s "$config" "$installed_config" || { printf 'Installed MOTD config differs from the profile.\n' >&2; exit 1; }

rendered=$(GROOMLAKE_ETC_ROOT="$target_root/etc" "$renderer")
expected=$(cat "$config")
[[ "$rendered" == "$expected" ]] || { printf 'Rendered MOTD differs from the profile.\n' >&2; exit 1; }
