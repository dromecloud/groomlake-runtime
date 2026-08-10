#!/usr/bin/env bash
set -Eeuo pipefail

# Publishes the commit.txt marker for the CURRENT HEAD, pushes it, and then
# verifies live against ATIS that manifest_version and the served commit are
# mutually consistent. Exists because the two-step dance (content commit,
# THEN a separate commit.txt-pointing-at-it commit) is easy to half-do -- a
# skipped or delayed second step leaves ATIS internally inconsistent and a
# real provisioning ticket then fails at MSR's manifest-verification step,
# before any component (even motd) installs. See docs/DEVELOPMENT-LOG.md,
# 2026-08-10 entry, for the incident this script exists to prevent.
#
# Usage: scripts/publish.sh
# Run this as the NEXT command after any commit that changes manifest.json
# or other runtime content -- never leave it for later.

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo_root"

git diff --quiet && git diff --cached --quiet \
  || { printf 'Working tree is not clean -- commit or stash your changes first.\n' >&2; exit 1; }

current_marker=$(cat public/commit.txt 2>/dev/null || printf '')
head_commit=$(git rev-parse HEAD)

if [[ "$current_marker" == "$head_commit" ]]; then
  printf 'commit.txt already points at HEAD (%s) -- nothing to publish.\n' "$head_commit"
else
  printf '%s' "$head_commit" > public/commit.txt
  git add public/commit.txt
  git commit -m "chore: publish commit marker ($head_commit)"
  git push origin main
  printf 'Published commit.txt -> %s\n' "$head_commit"
fi

printf 'Verifying live ATIS consistency...\n'
for attempt in 1 2 3 4 5; do
  atis_json=$(curl -fsS "https://groomlake-runtime.aero.drome.cloud/atis.php") || atis_json=''
  atis_commit=$(curl -fsSI "https://groomlake-runtime.aero.drome.cloud/atis.php" 2>/dev/null \
    | tr -d '\r' | awk -F': ' 'tolower($1)=="x-groomlake-commit"{print $2}')
  atis_manifest_version=$(printf '%s' "$atis_json" | jq -r '.manifest_version // empty' 2>/dev/null || printf '')
  local_manifest_version=$(jq -r '.manifest_version' manifest.json)
  head_manifest_version=$(git show "${atis_commit:-HEAD}:manifest.json" 2>/dev/null | jq -r '.manifest_version // empty')

  if [[ "$atis_commit" == "$head_commit" && "$atis_manifest_version" == "$local_manifest_version" \
        && "$head_manifest_version" == "$local_manifest_version" ]]; then
    printf 'OK: ATIS commit=%s manifest_version=%s -- consistent.\n' "$atis_commit" "$atis_manifest_version"
    exit 0
  fi
  printf '  attempt %s/5: ATIS not yet consistent (commit=%s manifest_version=%s, expected commit=%s manifest_version=%s) -- retrying in 3s...\n' \
    "$attempt" "${atis_commit:-<none>}" "${atis_manifest_version:-<none>}" "$head_commit" "$local_manifest_version"
  sleep 3
done

printf 'FAIL: ATIS did not converge to a consistent state after 5 attempts.\n' >&2
printf 'Do NOT trigger a real server test until this resolves -- it will fail the same way the 2026-08-10 incident did.\n' >&2
exit 1
