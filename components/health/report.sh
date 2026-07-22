#!/usr/bin/env bash
set -Eeuo pipefail

readonly ENV_FILE=/etc/groomlake/health.env
readonly PLAN_FILE=/etc/groomlake/install-plan.json
readonly STATUS_FILE=/var/lib/mission-systems-officer/boot-status.json
readonly SEQUENCE_FILE=/var/lib/mission-systems-officer/acars-sequence
readonly LOCK_FILE=/var/lib/mission-systems-officer/acars-sequence.lock
readonly RUNTIME_DIR=/opt/groomlake-runtime

[[ ${EUID:-$(id -u)} -eq 0 ]] || exit 77
[[ -r "$ENV_FILE" ]] || exit 66
# shellcheck disable=SC1091
source "$ENV_FILE"
[[ "$MSO_HEALTH_URL" == https://toolhub.horizon-hub.one/assets/groomlake-health.php ]] || exit 78
[[ "$MSO_HEALTH_TOKEN" =~ ^[0-9a-f]{64}$ ]] || exit 78

mkdir -p "$(dirname "$SEQUENCE_FILE")"
exec 9>"$LOCK_FILE"
flock -x 9
sequence=0
if [[ -s "$SEQUENCE_FILE" ]] && [[ "$(cat "$SEQUENCE_FILE")" =~ ^[0-9]+$ ]]; then sequence=$(cat "$SEQUENCE_FILE"); fi
sequence=$((sequence + 1))
printf '%s\n' "$sequence" > "$SEQUENCE_FILE"
chmod 0600 "$SEQUENCE_FILE" "$LOCK_FILE"

bootstrap_status='running'
bootstrap_task='bootstrap_running'
bootstrap_detail=''
if [[ -r "$STATUS_FILE" ]] && jq -e . "$STATUS_FILE" >/dev/null 2>&1; then
  bootstrap_status=$(jq -r '.status // "running"' "$STATUS_FILE")
  bootstrap_task=$(jq -r '.current_task // .task // "bootstrap_running"' "$STATUS_FILE")
  bootstrap_detail=$(jq -r '.error // .detail // empty' "$STATUS_FILE" | tr '\n' ' ' | cut -c1-300)
fi
[[ "$bootstrap_status" =~ ^(pending|running|complete|failed|stale)$ ]] || bootstrap_status='running'

plan_manifest=''
plan_commit=''
plan_version=''
if [[ -r "$PLAN_FILE" ]] && jq -e . "$PLAN_FILE" >/dev/null 2>&1; then
  plan_manifest=$(jq -r '.runtime.manifest_sha256 // empty' "$PLAN_FILE")
  plan_commit=$(jq -r '.runtime.commit // empty' "$PLAN_FILE")
  plan_version=$(jq -r '.runtime.manifest_version // empty' "$PLAN_FILE")
fi
current_commit=''
current_manifest=''
if [[ -d "$RUNTIME_DIR/.git" ]]; then
  current_commit=$(git -C "$RUNTIME_DIR" rev-parse HEAD 2>/dev/null || true)
  if [[ -f "$RUNTIME_DIR/manifest.json" ]]; then
    current_manifest=$(sha256sum "$RUNTIME_DIR/manifest.json" 2>/dev/null | awk '{print $1}' || true)
  fi
fi

checks='[]'
errors='[]'
add_check() { checks=$(jq -cn --argjson old "$checks" --arg id "$1" --arg status "$2" --arg detail "${3:-}" '$old + [{id:$id,status:$status,detail:$detail}]'); }
add_error() { errors=$(jq -cn --argjson old "$errors" --arg id "$1" --arg detail "${2:-}" '$old + [{id:$id,status:"failed",detail:$detail}]'); }
add_check msr_bootstrap "$([[ "$bootstrap_status" == failed ]] && echo failed || echo "$bootstrap_status")" "$bootstrap_task"
if [[ -n "$plan_commit" && "$plan_commit" == "$current_commit" ]]; then add_check runtime_checkout pass 'runtime commit matches install plan'; else add_check runtime_checkout failed 'runtime commit mismatch or checkout missing'; add_error runtime_checkout 'runtime commit mismatch'; fi
if [[ -n "$plan_manifest" && "$plan_manifest" == "$current_manifest" ]]; then add_check manifest_integrity pass 'manifest SHA-256 matches install plan'; else add_check manifest_integrity failed 'manifest SHA-256 mismatch or manifest missing'; add_error manifest_integrity 'manifest integrity check failed'; fi
add_check health_reporter pass 'reporter is running'

status='running'
task="$bootstrap_task"
if [[ "$bootstrap_status" == failed || "$errors" != '[]' ]]; then status='failed'; task='bootstrap_failed'; add_error msr_bootstrap "${bootstrap_detail:-bootstrap reported failure}"; elif [[ "$bootstrap_status" == complete ]]; then status='complete'; task='idle'; fi
hostname_value=$(hostname 2>/dev/null | cut -c1-255 || printf 'unknown')
bootstrap_version=${MSO_BOOTSTRAP_VERSION:-unknown}
payload=$(jq -cn \
  --argjson sequence "$sequence" \
  --arg hostname "$hostname_value" \
  --arg profile "${MSO_PROFILE:-unknown}" \
  --arg bootstrap_version "$bootstrap_version" \
  --arg runtime_commit "$current_commit" \
  --arg manifest_version "$plan_version" \
  --arg status "$status" \
  --arg current_task "$task" \
  --argjson checks "$checks" \
  --argjson errors "$errors" \
  '{schema_version:1,sequence:$sequence,hostname:$hostname,profile:$profile,bootstrap_version:$bootstrap_version,runtime_commit:$runtime_commit,manifest_version:$manifest_version,status:$status,current_task:$current_task,checks:$checks,errors:$errors}')
curl --fail-with-body --silent --show-error --proto '=https' --tlsv1.2 --max-time 10 \
  -X POST "$MSO_HEALTH_URL" \
  -H "Authorization: Bearer $MSO_HEALTH_TOKEN" \
  -H 'Content-Type: application/json' \
  --data-binary "$payload" >/dev/null
