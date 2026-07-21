#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/groomlake-msr-test.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

target_root="$work_dir/root"
plan="$work_dir/plan.json"
mkdir -p "$target_root"

printf '%s\n' \
  '{' \
  '  "schema_version": 1,' \
  '  "run_id": "local-motd-smoke",' \
  '  "profile": "ironbird"' \
  '}' > "$plan"

"$repo_root/bin/msr" apply --plan "$plan" --root "$target_root"
"$repo_root/bin/msr" apply --plan "$plan" --root "$target_root"

cmp -s \
  "$repo_root/profiles/ironbird/config/motd.txt" \
  "$target_root/etc/groomlake/motd.txt"
[[ -x "$target_root/etc/update-motd.d/10-groomlake-profile" ]]

rendered=$(GROOMLAKE_ETC_ROOT="$target_root/etc" "$target_root/etc/update-motd.d/10-groomlake-profile")
expected=$(cat "$repo_root/profiles/ironbird/config/motd.txt")
[[ "$rendered" == "$expected" ]]

unknown_plan="$work_dir/unknown-plan.json"
printf '%s\n' \
  '{' \
  '  "schema_version": 1,' \
  '  "run_id": "unknown-profile-smoke",' \
  '  "profile": "unknown"' \
  '}' > "$unknown_plan"

if "$repo_root/bin/msr" apply --plan "$unknown_plan" --root "$target_root" >/dev/null 2>&1; then
  printf 'Unknown profile was not rejected.\n' >&2
  exit 1
fi

printf 'MSR MOTD smoke test passed.\n'
