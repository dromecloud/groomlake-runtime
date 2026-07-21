#!/usr/bin/env bash
set -Eeuo pipefail

die() {
  printf 'build-release: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Usage: scripts/build-release.sh [--commit <git-ref>] [--output <directory>]

Builds a deterministic runtime archive and a flattened release-manifest.json.
The working tree must be clean so the release always describes an exact commit.
EOF
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die 'sha256sum or shasum is required.'
  fi
}

safe_relative_path() {
  local path=$1
  [[ -n "$path" ]] || die 'Empty manifest path.'
  [[ "$path" != /* ]] || die "Absolute manifest path is forbidden: $path"
  [[ ! "$path" =~ (^|/)\.\.(/|$) ]] || die "Parent traversal is forbidden: $path"
  [[ "$path" =~ ^[A-Za-z0-9._/-]+$ ]] || die "Unsupported characters in manifest path: $path"
}

extract_blob() {
  local commit=$1
  local path=$2
  local output=$3
  safe_relative_path "$path"
  git cat-file -e "$commit:$path" 2>/dev/null || die "Declared file is missing from commit: $path"
  git show "$commit:$path" > "$output"
}

ref='HEAD'
output='dist'

while (( $# > 0 )); do
  case "$1" in
    --commit)
      (( $# >= 2 )) || { usage; exit 64; }
      ref=$2
      shift 2
      ;;
    --output)
      (( $# >= 2 )) || { usage; exit 64; }
      output=$2
      shift 2
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

for command_name in git jq gzip awk; do
  command -v "$command_name" >/dev/null 2>&1 || die "$command_name is required."
done

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo_root"

[[ -z "$(git status --porcelain)" ]] || die 'Working tree is not clean.'
commit=$(git rev-parse --verify "$ref^{commit}") || die "Unknown Git reference: $ref"
short_commit=${commit:0:12}
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/groomlake-release.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

catalog_file="$work_dir/catalog.json"
profiles_file="$work_dir/profiles.json"
components_file="$work_dir/components.json"
extract_blob "$commit" 'manifest.json' "$catalog_file"

jq -e '
  type == "object" and
  .schema_version == 2 and
  .runtime.id == "groomlake-runtime" and
  .runtime.repository == "dromecloud/groomlake-runtime" and
  .runtime.entrypoint == "bin/msr" and
  (.profiles | type == "object" and length > 0) and
  (.components | type == "object" and length > 0)
' "$catalog_file" >/dev/null || die 'Runtime manifest is invalid.'

printf '{}\n' > "$profiles_file"
while IFS= read -r profile_id; do
  profile_path=$(jq -er --arg id "$profile_id" '.profiles[$id].manifest' "$catalog_file") \
    || die "Missing profile manifest path: $profile_id"
  profile_file="$work_dir/profile-$profile_id.json"
  extract_blob "$commit" "$profile_path" "$profile_file"
  jq -e --arg id "$profile_id" '
    type == "object" and
    .schema_version == 2 and
    .id == $id and
    (.components | type == "array" and length > 0) and
    (([.components[].id] | unique | length) == (.components | length)) and
    (all(.components[];
      (.id | type == "string") and
      (.config | type == "string" and length > 0) and
      (.required | type == "boolean") and
      (.default_enabled | type == "boolean") and
      ((.required == false) or (.default_enabled == true)) and
      (.depends_on | type == "array")
    )) and
    (.sequences | type == "array")
  ' "$profile_file" >/dev/null || die "Profile manifest is invalid: $profile_id"

  profile_dir=$(dirname "$profile_path")
  while IFS=$'\t' read -r component_id config_path; do
    jq -e --arg id "$component_id" '.components[$id] != null' "$catalog_file" >/dev/null \
      || die "Profile $profile_id references unregistered component: $component_id"
    extract_blob "$commit" "$profile_dir/$config_path" "$work_dir/config-$profile_id-$component_id"
  done < <(jq -r '.components[] | [.id, .config] | @tsv' "$profile_file")

  while IFS=$'\t' read -r component_id dependency_id; do
    [[ "$component_id" != "$dependency_id" ]] || die "Component depends on itself: $component_id"
    jq -e --arg id "$dependency_id" 'any(.components[]; .id == $id)' "$profile_file" >/dev/null \
      || die "Component $component_id depends on missing profile component: $dependency_id"
  done < <(jq -r '.components[] as $component | $component.depends_on[]? | [$component.id, .] | @tsv' "$profile_file")

  jq --arg id "$profile_id" --slurpfile definition "$profile_file" \
    '. + {($id): $definition[0]}' "$profiles_file" > "$profiles_file.next"
  mv "$profiles_file.next" "$profiles_file"
done < <(jq -r '.profiles | keys[]' "$catalog_file")

printf '{}\n' > "$components_file"
while IFS= read -r component_id; do
  component_path=$(jq -er --arg id "$component_id" '.components[$id].manifest' "$catalog_file") \
    || die "Missing component manifest path: $component_id"
  component_file="$work_dir/component-$component_id.json"
  extract_blob "$commit" "$component_path" "$component_file"
  jq -e --arg id "$component_id" '
    type == "object" and
    .schema_version == 1 and
    .id == $id and
    (.install | type == "string" and length > 0) and
    (.verify | type == "string" and length > 0)
  ' "$component_file" >/dev/null || die "Component manifest is invalid: $component_id"

  component_dir=$(dirname "$component_path")
  install_path=$(jq -r '.install' "$component_file")
  verify_path=$(jq -r '.verify' "$component_file")
  extract_blob "$commit" "$component_dir/$install_path" "$work_dir/install-$component_id"
  extract_blob "$commit" "$component_dir/$verify_path" "$work_dir/verify-$component_id"

  jq --arg id "$component_id" --slurpfile definition "$component_file" \
    '. + {($id): $definition[0]}' "$components_file" > "$components_file.next"
  mv "$components_file.next" "$components_file"
done < <(jq -r '.components | keys[]' "$catalog_file")

mkdir -p "$output"
output_dir=$(cd "$output" && pwd -P)
archive_filename="groomlake-runtime-$short_commit.tar.gz"
archive_path="$output_dir/$archive_filename"
release_manifest="$output_dir/release-manifest.json"

git archive --format=tar "$commit" | gzip -n > "$archive_path"
archive_sha=$(sha256_file "$archive_path")

jq -S -n \
  --arg repository 'dromecloud/groomlake-runtime' \
  --arg commit "$commit" \
  --arg archive_filename "$archive_filename" \
  --arg archive_sha "$archive_sha" \
  --slurpfile catalog "$catalog_file" \
  --slurpfile profiles "$profiles_file" \
  --slurpfile components "$components_file" \
  '{
    schema_version: 1,
    release: {
      repository: $repository,
      commit: $commit,
      archive: {
        filename: $archive_filename,
        sha256: $archive_sha
      }
    },
    catalog: $catalog[0],
    definitions: {
      profiles: $profiles[0],
      components: $components[0]
    }
  }' > "$release_manifest"

release_sha=$(sha256_file "$release_manifest")
printf '%s  %s\n' "$archive_sha" "$archive_filename" > "$archive_path.sha256"
printf '%s  %s\n' "$release_sha" 'release-manifest.json' > "$release_manifest.sha256"

printf 'Release commit: %s\n' "$commit"
printf 'Runtime archive: %s\n' "$archive_path"
printf 'Release manifest: %s\n' "$release_manifest"
