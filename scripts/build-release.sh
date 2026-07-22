#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/build-release.sh --profile <id> --output <archive.tar.gz> [--component <id> ...]

Builds a minimal, reproducible Runtime archive. The archive contains only the
MSR core, the selected profile, its selected components, schemas and the
manifest. It never contains .git, tests, docs or other profiles.
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
profile=''
output=''
requested_components=()

while (( $# > 0 )); do
  case "$1" in
    --profile) (( $# >= 2 )) || { usage; exit 64; }; profile=$2; shift 2 ;;
    --output) (( $# >= 2 )) || { usage; exit 64; }; output=$2; shift 2 ;;
    --component) (( $# >= 2 )) || { usage; exit 64; }; requested_components+=("$2"); shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) usage; exit 64 ;;
  esac
done

[[ "$profile" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] || die 'Profile is invalid.'
[[ -n "$output" ]] || die '--output is required.'
[[ "$output" == /* ]] || die '--output must be an absolute path.'
command -v jq >/dev/null 2>&1 || die 'jq is required.'
command -v tar >/dev/null 2>&1 || die 'tar is required.'

manifest="$repo_root/manifest.json"
profile_file=$(jq -er --arg id "$profile" '.profiles[$id].manifest // empty' "$manifest") \
  || die "Profile is not registered: $profile"
profile_file="$repo_root/$profile_file"
[[ -r "$profile_file" ]] || die "Profile manifest is missing: $profile_file"

profile_components=()
while IFS= read -r component; do
  [[ -n "$component" ]] && profile_components+=("$component")
done < <(jq -r '.components[] | select(.required or .default_enabled) | .id' "$profile_file")
if ((${#requested_components[@]} > 0)); then
  selected_components=("${requested_components[@]}")
else
  selected_components=("${profile_components[@]}")
fi

contains() {
  local needle=$1 item
  shift
  for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
  return 1
}

for component in "${selected_components[@]}"; do
  [[ "$component" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] || die "Component is invalid: $component"
  contains "$component" "${profile_components[@]}" \
    || die "Component is not enabled by profile $profile: $component"
done

for component in "${profile_components[@]}"; do
  required=$(jq -r --arg id "$component" '.components[] | select(.id == $id) | .required' "$profile_file")
  if [[ "$required" == true ]] && ! contains "$component" "${selected_components[@]}"; then
    die "Required component was omitted: $component"
  fi
done

commit=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null) || die 'Runtime checkout is not a Git repository.'
manifest_version=$(jq -er '.manifest_version' "$manifest")
manifest_sha=$(if command -v sha256sum >/dev/null 2>&1; then sha256sum "$manifest" | awk '{print $1}'; else shasum -a 256 "$manifest" | awk '{print $1}'; fi)

stage=$(mktemp -d "${TMPDIR:-/tmp}/groomlake-release.XXXXXX")
cleanup() { rm -rf "$stage"; }
trap cleanup EXIT

mkdir -p "$stage/bin" "$stage/schemas" "$stage/profiles/$(dirname "${profile_file#"$repo_root/profiles/"}")" "$stage/components"
cp "$repo_root/bin/msr" "$stage/bin/msr"
cp "$manifest" "$stage/manifest.json"
cp -R "$repo_root/schemas/." "$stage/schemas/"
profile_relative=${profile_file#"$repo_root/"}
profile_dir=$(dirname "$profile_relative")
mkdir -p "$stage/$profile_dir"
cp -R "$repo_root/$profile_dir/." "$stage/$profile_dir/"

for component in "${selected_components[@]}"; do
  component_relative=$(jq -er --arg id "$component" '.components[$id].manifest // empty' "$manifest") \
    || die "Component is not registered: $component"
  component_dir=$(dirname "$component_relative")
  [[ "$component_dir" == "components/$component" ]] || die "Component path is not canonical: $component"
  mkdir -p "$stage/$component_dir"
  cp -R "$repo_root/$component_dir/." "$stage/$component_dir/"
done

cat > "$stage/release.json" <<EOF
{
  "schema_version": 1,
  "runtime_id": "groomlake-runtime",
  "manifest_version": "$manifest_version",
  "manifest_sha256": "$manifest_sha",
  "commit": "$commit",
  "profile": "$profile",
  "components": $(printf '%s\n' "${selected_components[@]}" | jq -R . | jq -s .)
}
EOF

mkdir -p "$(dirname "$output")"
tar -C "$stage" -czf "$output" .
archive_sha=$(if command -v sha256sum >/dev/null 2>&1; then sha256sum "$output" | awk '{print $1}'; else shasum -a 256 "$output" | awk '{print $1}'; fi)
printf 'Release: %s\nProfile: %s\nComponents: %s\nSHA256: %s\n' \
  "$output" "$profile" "${selected_components[*]}" "$archive_sha"
