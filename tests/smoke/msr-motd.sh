#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/groomlake-msr-test.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

target_root="$work_dir/root"
plan="$work_dir/plan.json"
mkdir -p "$target_root"
manifest_version=$(jq -r '.manifest_version' "$repo_root/manifest.json")
manifest_sha=$(shasum -a 256 "$repo_root/manifest.json" | awk '{print $1}')
runtime_commit=$(git -C "$repo_root" rev-parse HEAD)

write_plan() {
  local profile=$1 output=$2
  printf '%s\n' \
    '{' \
    '  "schema_version": 2,' \
    '  "runtime": {' \
    "    \"manifest_version\": \"$manifest_version\"," \
    "    \"manifest_sha256\": \"$manifest_sha\"," \
    "    \"commit\": \"$runtime_commit\"" \
    '  },' \
    '  "run_id": "local-motd-smoke",' \
    "  \"profile\": \"$profile\"" \
    '}' > "$output"
}

write_plan ironbird "$plan"
"$repo_root/bin/msr" apply --plan "$plan" --root "$target_root"
"$repo_root/bin/msr" apply --plan "$plan" --root "$target_root"

cmp -s "$repo_root/profiles/ironbird/config/motd.txt" "$target_root/etc/groomlake/motd.txt"
[[ -x "$target_root/etc/update-motd.d/10-groomlake-profile" ]]
rendered=$(GROOMLAKE_ETC_ROOT="$target_root/etc" "$target_root/etc/update-motd.d/10-groomlake-profile")
expected=$(cat "$repo_root/profiles/ironbird/config/motd.txt")
[[ "$rendered" == "$expected" ]]

unknown_plan="$work_dir/unknown-plan.json"
write_plan unknown "$unknown_plan"
if "$repo_root/bin/msr" apply --plan "$unknown_plan" --root "$target_root" >/dev/null 2>&1; then
  printf 'Unknown profile was not rejected.\n' >&2
  exit 1
fi

mismatch_plan="$work_dir/mismatch-plan.json"
write_plan ironbird "$mismatch_plan"
jq '.runtime.manifest_version = "2099.01.01.1"' "$mismatch_plan" > "$mismatch_plan.next"
mv "$mismatch_plan.next" "$mismatch_plan"
if "$repo_root/bin/msr" apply --plan "$mismatch_plan" --root "$target_root" >/dev/null 2>&1; then
  printf 'Manifest version mismatch was not rejected.\n' >&2
  exit 1
fi

printf 'MSR MOTD smoke test passed.\n'
