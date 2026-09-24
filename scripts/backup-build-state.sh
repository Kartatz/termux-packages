#!/usr/bin/env bash
set -eu -o pipefail

CONTAINER="${TERMUX_BUILDER_CONTAINER:-termux-package-builder}"
ARCH="aarch64"
MAX_ASSETS_PER_RELEASE=1000
STATE_FILE="build-state.tar.xz"

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(git -C "$REPO_DIR" remote get-url origin | sed -e 's|^.*github.com/||' -e 's|\.git$||')"
BUILDALL_DIR="/home/builder/.termux-build/_buildall-$ARCH"

usage() {
	echo "Usage: $(basename "$0") [backup|restore]"
}

backup() {
	STAGE="$(mktemp -d "${TMPDIR:-/tmp}/termux-build-backup.XXXXXXXX")"
	trap 'rm -rf "$STAGE"' EXIT

	mkdir -p "$STAGE/build-all"
	docker cp "$CONTAINER:$BUILDALL_DIR/buildorder.txt" "$STAGE/build-all/"
	docker cp "$CONTAINER:$BUILDALL_DIR/buildstatus.txt" "$STAGE/build-all/"

	tar -C "$STAGE" -cf - build-all | xz -T 0 -6 >"$STAGE/$STATE_FILE"

	local existing_names
	existing_names="$(gh api --paginate "repos/$REPO/releases" --jq '.[].assets[].name')"

	asset_exists() {
		printf '%s\n' "$existing_names" | grep -qxF "$1"
	}

	# Create a new release, or reuse the release that already holds the
	# build state file so repeated backups do not pile up releases.
	create_release() {
		local tag
		if [ -n "$existing_tag" ]; then
			tag="$(gh api "repos/$REPO/releases?per_page=100" \
				--jq ".[] | select(any(.assets[]; .name == \"$existing_tag\")) | .tag_name" | head -n1)"
			if [ -n "$tag" ]; then
				echo "$tag"
				return 0
			fi
		fi
		local out
		while :; do
			local new_tag
			new_tag="$(date +%Y%m%d-%H%M%S)"
			if out="$(gh release create "$new_tag" -R "$REPO" --title "$new_tag" \
				--notes "Termux GCC toolchain build state and .deb packages." 2>&1)"; then
				echo "$new_tag"
				return 0
			fi
			if ! grep -qi "already exists" <<<"$out"; then
				echo "ERROR: failed to create release: $out" >&2
				return 1
			fi
			sleep 1
		done
	}

	tag="$(existing_tag="$STATE_FILE" create_release)"
	count=0

	gh release upload "$tag" -R "$REPO" "$STAGE/$STATE_FILE" --clobber >/dev/null
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
}

restore() {
	STAGE="$(mktemp -d "${TMPDIR:-/tmp}/termux-build-restore.XXXXXXXX")"
	trap 'rm -rf "$STAGE"' EXIT

	local tag releases_json
	releases_json="$(gh api "repos/$REPO/releases?per_page=100")"

	tag="$(jq -r --arg f "$STATE_FILE" \
		'sort_by(.created_at) | reverse | map(select(any(.assets[]; .name == $f))) | first | .tag_name // empty' \
		<<<"$releases_json")"
	if [ -z "$tag" ]; then
		echo "ERROR: no release containing $STATE_FILE found" >&2
		exit 1
	fi

	gh release download "$tag" -R "$REPO" --pattern "$STATE_FILE" --dir "$STAGE"
	tar -C "$STAGE" -xf "$STAGE/$STATE_FILE"

	docker exec "$CONTAINER" mkdir -p "$BUILDALL_DIR"
	docker cp "$STAGE/build-all/buildorder.txt" "$CONTAINER:$BUILDALL_DIR/buildorder.txt"
	docker cp "$STAGE/build-all/buildstatus.txt" "$CONTAINER:$BUILDALL_DIR/buildstatus.txt"
	echo "Restored build state from $tag into $CONTAINER:$BUILDALL_DIR"

	mkdir -p "$REPO_DIR/output"
	local -a deb_tags
	mapfile -t deb_tags < <(jq -r \
		'sort_by(.created_at) | reverse | .[] | select(any(.assets[]; (.name|endswith(".deb")))) | .tag_name' \
		<<<"$releases_json")
	for tag in "${deb_tags[@]}"; do
		gh release download "$tag" -R "$REPO" --pattern '*.deb' \
			--dir "$REPO_DIR/output" --skip-existing >/dev/null
	done
	echo "Restored $(ls "$REPO_DIR"/output/*.deb | wc -l) debs to $REPO_DIR/output"
}

case "${1:-backup}" in
	backup) backup;;
	restore) restore;;
	*) usage >&2; exit 1;;
esac
