#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/groomlake-release-smoke.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

first="$work_dir/first"
second="$work_dir/second"
"$repo_root/scripts/build-release.sh" --commit HEAD --output "$first" >/dev/null
"$repo_root/scripts/build-release.sh" --commit HEAD --output "$second" >/dev/null

archive_filename=$(jq -r '.release.archive.filename' "$first/release-manifest.json")
archive_sha=$(jq -r '.release.archive.sha256' "$first/release-manifest.json")

cmp -s "$first/release-manifest.json" "$second/release-manifest.json"
cmp -s "$first/$archive_filename" "$second/$archive_filename"

if command -v sha256sum >/dev/null 2>&1; then
  actual_archive_sha=$(sha256sum "$first/$archive_filename" | awk '{print $1}')
else
  actual_archive_sha=$(shasum -a 256 "$first/$archive_filename" | awk '{print $1}')
fi
[[ "$archive_sha" == "$actual_archive_sha" ]]

jq -e '
  .schema_version == 1 and
  (.release.commit | test("^[0-9a-f]{40}$")) and
  (.release.archive.sha256 | test("^[0-9a-f]{64}$")) and
  .catalog.schema_version == 2 and
  .definitions.profiles.ironbird.id == "ironbird" and
  .definitions.components.motd.id == "motd"
' "$first/release-manifest.json" >/dev/null

for expected_path in \
  bin/msr \
  components/motd/component.json \
  manifest.json \
  profiles/ironbird/profile.json; do
  tar -tzf "$first/$archive_filename" | grep -Fqx "$expected_path"
done

printf 'Runtime release-manifest smoke test passed.\n'
