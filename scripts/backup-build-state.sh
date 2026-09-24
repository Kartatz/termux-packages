#!/usr/bin/env bash
set -eu -o pipefail

CONTAINER="${TERMUX_BUILDER_CONTAINER:-termux-package-builder}"
ARCH="aarch64"
OUTPUT="termux-build-backup_${ARCH}_$(date +%Y%m%d-%H%M).tar.xz"

while [ $# -gt 0 ]; do
	case "$1" in
		-o) OUTPUT="$2"; shift 2;;
		*) echo "Usage: $(basename "$0") [-o FILE.tar.xz]" >&2; exit 1;;
	esac
done

BUILDALL_DIR="/home/builder/.termux-build/_buildall-$ARCH"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/termux-build-backup.XXXXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/build-all" "$STAGE/output"

docker cp "$CONTAINER:$BUILDALL_DIR/buildorder.txt" "$STAGE/build-all/"
docker cp "$CONTAINER:$BUILDALL_DIR/buildstatus.txt" "$STAGE/build-all/"

cp "$(dirname "$0")/../output"/*.deb "$STAGE/output/"

tar -C "$STAGE" -cf - build-all output | xz -T 0 -6 >"$OUTPUT"

echo "Wrote $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
sha256sum "$OUTPUT"
