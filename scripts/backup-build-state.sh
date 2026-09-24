#!/usr/bin/env bash
set -eu -o pipefail

CONTAINER="${TERMUX_BUILDER_CONTAINER:-termux-package-builder}"
ARCH="aarch64"
OUTPUT="termux-build-backup_${ARCH}_$(date +%Y%m%d-%H%M).tar.xz"
RELEASE_PREFIX="deb-backup-"
MAX_ASSETS_PER_RELEASE=1000

while [ $# -gt 0 ]; do
	case "$1" in
		-o) OUTPUT="$2"; shift 2;;
		*) echo "Usage: $(basename "$0") [-o FILE.tar.xz]" >&2; exit 1;;
	esac
done

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(git -C "$REPO_DIR" remote get-url origin | sed -e 's|^.*github.com/||' -e 's|\.git$||')"
BUILDALL_DIR="/home/builder/.termux-build/_buildall-$ARCH"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/termux-build-backup.XXXXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/build-all"
docker cp "$CONTAINER:$BUILDALL_DIR/buildorder.txt" "$STAGE/build-all/"
docker cp "$CONTAINER:$BUILDALL_DIR/buildstatus.txt" "$STAGE/build-all/"

tar -C "$STAGE" -cf - build-all | xz -T 0 -6 >"$OUTPUT"
echo "Wrote $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
sha256sum "$OUTPUT"

releases_json="$(gh api --paginate "repos/$REPO/releases")"
mapfile -t existing_names < <(jq -r '.[].assets[].name' <<<"$releases_json")
mapfile -t series < <(jq -r --arg p "$RELEASE_PREFIX" \
	'.[] | select(.tag_name | startswith($p)) | [.tag_name, (.assets|length)] | @tsv' \
	<<<"$releases_json" | sort -V)

asset_exists() {
	local line
	for line in "${existing_names[@]:-}"; do
		[ "$line" = "$1" ] && return 0
	done
	return 1
}

current_tag=""
current_count=0
if ((${#series[@]})); then
	current_tag="${series[-1]%%$'\t'*}"
	current_count="${series[-1]#*$'\t'}"
fi

shopt -s nullglob
for file in "$REPO_DIR"/output/*.deb; do
	name="$(basename "$file")"
	if asset_exists "$name"; then
		echo "Skipping $name (already in a release)"
		continue
	fi
	if [ -z "$current_tag" ] || [ "$current_count" -ge "$MAX_ASSETS_PER_RELEASE" ]; then
		if [ -z "$current_tag" ]; then
			next=1
		else
			next=$(( ${current_tag#"$RELEASE_PREFIX"} + 1 ))
		fi
		current_tag="${RELEASE_PREFIX}${next}"
		gh release create "$current_tag" -R "$REPO" \
			--title "deb-backup $next" \
			--notes "Built .deb packages, part $next." >/dev/null
		current_count=0
	fi
	gh release upload "$current_tag" -R "$REPO" "$file" >/dev/null
	current_count=$((current_count + 1))
	echo "Uploaded $name to $current_tag ($current_count/$MAX_ASSETS_PER_RELEASE)"
done
