#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo_root"

bash -n \
  bin/msr \
  components/motd/install.sh \
  components/motd/verify.sh \
  scripts/check.sh \
  tests/smoke/msr-motd.sh
sh -n components/motd/render.sh

find . -path './.git' -prune -o -name '*.json' -type f -print0 \
  | xargs -0 -n1 jq -e . >/dev/null

tests/smoke/msr-motd.sh
git diff --check
printf 'All Groomlake Runtime checks passed.\n'
