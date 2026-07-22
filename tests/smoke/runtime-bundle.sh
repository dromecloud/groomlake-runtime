#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/groomlake-bundle-test.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

archive="$work_dir/runtime.tar.gz"
bundle="$work_dir/bundle"
target_root="$work_dir/root"
plan="$work_dir/plan.json"
mkdir -p "$bundle" "$target_root"

bash "$repo_root/scripts/build-release.sh" --profile ironbird --output "$archive" >/dev/null
tar -xzf "$archive" -C "$bundle"

manifest_version=$(jq -r '.manifest_version' "$bundle/release.json")
manifest_sha=$(jq -r '.manifest_sha256' "$bundle/release.json")
runtime_commit=$(jq -r '.commit' "$bundle/release.json")
jq -n \
  --arg version "$manifest_version" \
  --arg sha "$manifest_sha" \
  --arg commit "$runtime_commit" \
  '{schema_version:2,runtime:{manifest_version:$version,manifest_sha256:$sha,commit:$commit},run_id:"bundle-motd-smoke",profile:"ironbird"}' \
  > "$plan"

(cd /tmp && "$bundle/bin/msr" apply --plan "$plan" --root "$target_root")
[[ -f "$target_root/etc/groomlake/motd.txt" ]]
[[ -x "$target_root/etc/update-motd.d/10-groomlake-profile" ]]

if [[ -d "$bundle/.git" || -d "$bundle/tests" || -d "$bundle/docs" ]]; then
  printf 'Release bundle contains forbidden development paths.\n' >&2
  exit 1
fi

printf 'Runtime bundle smoke test passed.\n'
