#!/usr/bin/env bash
set -eu -o pipefail

CONTAINER="${TERMUX_BUILDER_CONTAINER:-termux-package-builder}"
ARCH="aarch64"
MAX_ASSETS_PER_RELEASE=1000

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(git -C "$REPO_DIR" remote get-url origin | sed -e 's|^.*github.com/||' -e 's|\.git$||')"
BUILDALL_DIR="/home/builder/.termux-build/_buildall-$ARCH"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/termux-build-backup.XXXXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/build-all"
docker cp "$CONTAINER:$BUILDALL_DIR/buildorder.txt" "$STAGE/build-all/"
docker cp "$CONTAINER:$BUILDALL_DIR/buildstatus.txt" "$STAGE/build-all/"

STATE_FILE="termux-build-backup_${ARCH}_$(date +%Y%m%d-%H%M%S).tar.xz"
tar -C "$STAGE" -cf - build-all | xz -T 0 -6 >"$STAGE/$STATE_FILE"

existing_names="$(gh api --paginate "repos/$REPO/releases" --jq '.[].assets[].name')"

asset_exists() {
	printf '%s\n' "$existing_names" | grep -qxF "$1"
}

create_release() {
	local tag out
	while :; do
		tag="$(date +%Y%m%d-%H%M%S)"
		if out="$(gh release create "$tag" -R "$REPO" --title "$tag" \
			--notes "Termux GCC toolchain build state and .deb packages." 2>&1)"; then
			echo "$tag"
			return 0
		fi
		if ! grep -qi "already exists" <<<"$out"; then
			echo "ERROR: failed to create release: $out" >&2
			return 1
		fi
		sleep 1
	done
}

tag="$(create_release)"
count=0

gh release upload "$tag" -R "$REPO" "$STAGE/$STATE_FILE" >/dev/null
count=$((count + 1))
echo "Uploaded $STATE_FILE to $tag ($count/$MAX_ASSETS_PER_RELEASE)"

shopt -s nullglob
for file in "$REPO_DIR"/output/*.deb; do
	name="$(basename "$file")"
	if asset_exists "$name"; then
		echo "Skipping $name (already in a release)"
		continue
	fi
	if [ "$count" -ge "$MAX_ASSETS_PER_RELEASE" ]; then
		tag="$(create_release)"
		count=0
	fi
	gh release upload "$tag" -R "$REPO" "$file" >/dev/null
	count=$((count + 1))
	echo "Uploaded $name to $tag ($count/$MAX_ASSETS_PER_RELEASE)"
done
