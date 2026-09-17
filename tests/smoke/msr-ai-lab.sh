#!/usr/bin/env bash
set -Eeuo pipefail

# ai-lab-langchain and ai-lab-openai-sdk perform real system changes (apt,
# useradd, venv/pip installs, a systemd unit) and therefore only support
# --root /, same as hermes and system-upgrade. A local smoke run can't
# safely exercise that path, so this test instead proves the
# manifest/profile/component wiring is correct: MSR must resolve and start
# each component, then fail with our own explicit --root / guard — never
# with a registration or config-resolution error, which would mean the
# wiring itself is broken.

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/groomlake-msr-ai-lab-test.XXXXXX")
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
    '  "run_id": "local-ai-lab-smoke",' \
    '  "profile": "ironbird",' \
    "  \"components\": $components_json" \
    '}' > "$output"
}

export MSO_HEALTH_URL='https://toolhub.horizon-hub.one/assets/groomlake-health.php'
export MSO_HEALTH_TOKEN='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
export MSO_SERVER_NAME='local-ai-lab-smoke'
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

assert_rejected_for_non_root_target '["motd", "health", "ai-lab-langchain"]' ai-lab-langchain
assert_rejected_for_non_root_target '["motd", "health", "ai-lab-openai-sdk"]' ai-lab-openai-sdk
assert_rejected_for_non_root_target '["motd", "health", "ai-lab-crewai"]' ai-lab-crewai
assert_rejected_for_non_root_target '["motd", "health", "ai-lab-langchain", "ai-lab-openai-sdk", "ai-lab-crewai"]' ai-lab-all

printf 'MSR ai-lab-langchain/ai-lab-openai-sdk/ai-lab-crewai registration smoke test passed.\n'
