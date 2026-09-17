#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo_root"

bash -n \
  bin/msr \
  components/motd/install.sh \
  components/motd/verify.sh \
  components/health/install.sh \
  components/health/verify.sh \
  components/health/report.sh \
  components/hermes/install.sh \
  components/hermes/verify.sh \
  components/system-upgrade/install.sh \
  components/system-upgrade/verify.sh \
  components/ai-lab-langchain/install.sh \
  components/ai-lab-langchain/verify.sh \
  components/ai-lab-openai-sdk/install.sh \
  components/ai-lab-openai-sdk/verify.sh \
  components/ai-lab-crewai/install.sh \
  components/ai-lab-crewai/verify.sh \
  scripts/check.sh \
  scripts/publish.sh \
  tests/smoke/msr-motd.sh \
  tests/smoke/msr-hermes.sh \
  tests/smoke/msr-ai-lab.sh
sh -n components/motd/render.sh

find . -path './.git' -prune -o -name '*.json' -type f -print0 \
  | xargs -0 -n1 jq -e . >/dev/null

tests/smoke/msr-motd.sh
tests/smoke/msr-hermes.sh
tests/smoke/msr-ai-lab.sh
git diff --check
printf 'All Groomlake Runtime checks passed.\n'
