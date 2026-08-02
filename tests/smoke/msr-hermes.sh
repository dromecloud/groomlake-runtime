#!/usr/bin/env bash
set -Eeuo pipefail

# Hermes and system-upgrade perform real system changes (apt, useradd, a
# verified external installer) and therefore only support --root /. A local
# smoke run can't safely exercise that path, so this test instead proves the
# manifest/profile/component wiring is correct: MSR must resolve and start
# each component, then fail with our own explicit --root / guard — never with
# a registration or config-resolution error, which would mean the wiring
# itself is broken.

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/groomlake-msr-hermes-test.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

target_root="$work_dir/root"
mkdir -p "$target_root"
manifest_version=$(jq -r '.manifest_version' "$repo_root/manifest.json")
manifest_sha=$(shasum -a 256 "$repo_root/manifest.json" | awk '{print $1}')
runtime_commit=$(git -C "$repo_root" rev-parse HEAD)

write_plan() {
  local components_json=$1 output=$2
  printf '%s\n' \
    '{' \
    '  "schema_version": 2,' \
    '  "runtime": {' \
    "    \"manifest_version\": \"$manifest_version\"," \
    "    \"manifest_sha256\": \"$manifest_sha\"," \
    "    \"commit\": \"$runtime_commit\"" \
    '  },' \
    '  "run_id": "local-hermes-smoke",' \
    '  "profile": "ironbird",' \
    "  \"components\": $components_json" \
    '}' > "$output"
}

export MSO_HEALTH_URL='https://toolhub.horizon-hub.one/assets/groomlake-health.php'
export MSO_HEALTH_TOKEN='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
export MSO_SERVER_NAME='local-hermes-smoke'
export MSO_PROFILE='ironbird'
export MSO_BOOTSTRAP_VERSION='smoke'

assert_rejected_for_non_root_target() {
  local components_json=$1 label=$2
  local plan="$work_dir/plan-$label.json" output="$work_dir/output-$label.txt"
  write_plan "$components_json" "$plan"
  if "$repo_root/bin/msr" apply --plan "$plan" --root "$target_root" >"$output" 2>&1; then
    printf '[%s] Expected rejection for a non-root target, but msr succeeded.\n' "$label" >&2
    cat "$output" >&2
    exit 1
  fi
  grep -q 'only supports --root /' "$output" \
    || { printf '[%s] Unexpected failure reason (wiring likely broken):\n' "$label" >&2; cat "$output" >&2; exit 1; }
}

assert_rejected_for_non_root_target '["motd", "health", "hermes"]' hermes
assert_rejected_for_non_root_target '["motd", "health", "system-upgrade"]' system-upgrade

printf 'MSR Hermes/system-upgrade registration smoke test passed.\n'
