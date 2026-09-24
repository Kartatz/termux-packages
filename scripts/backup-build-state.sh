#!/usr/bin/env bash
set -eu -o pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONTAINER="${TERMUX_BUILDER_CONTAINER:-termux-package-builder}"
ARCH="aarch64"
OUTPUT=""
WITH_CACHE=false
WITH_LOGS=false

usage() {
	echo "Usage: ./scripts/backup-build-state.sh [-a ARCH] [-o FILE.tar.xz] [--cache] [--logs]"
	echo ""
	echo "Backs up the minimal state needed to resume build-all.sh on a fresh machine"
	echo "from the '$CONTAINER' build container, compacted into a .tar.xz archive."
	echo ""
	echo "  -a      Architecture of the build (default: aarch64)."
	echo "  -o      Output archive path (default: ./termux-build-backup_<arch>_<date>.tar.xz)."
	echo "  --cache Also bundle the cross toolchain caches (~6 GiB uncompressed)."
	echo "  --logs  Also bundle the per-package build logs (*.out)."
	echo ""
	echo "The archive always contains the build order, the build status (already"
	echo "built packages) and all built .deb artifacts from the output/ directory."
}

while [ $# -gt 0 ]; do
	case "$1" in
		-a) ARCH="$2"; shift 2;;
		-o) OUTPUT="$2"; shift 2;;
		--cache) WITH_CACHE=true; shift;;
		--logs) WITH_LOGS=true; shift;;
		-h|--help) usage; exit 0;;
		*) usage >&2; exit 1;;
	esac
done

BUILDALL_DIR="/home/builder/.termux-build/_buildall-$ARCH"

docker inspect "$CONTAINER" >/dev/null 2>&1 || {
	echo "ERROR: container '$CONTAINER' is not running." >&2
	exit 1
}
docker exec "$CONTAINER" test -d "$BUILDALL_DIR" || {
	echo "ERROR: '$BUILDALL_DIR' does not exist inside '$CONTAINER'." >&2
	exit 1
}

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/termux-build-backup.XXXXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/build-all" "$STAGE/output"

docker cp "$CONTAINER:$BUILDALL_DIR/buildorder.txt" "$STAGE/build-all/" || {
	echo "ERROR: buildorder.txt not found in container." >&2
	exit 1
}
if docker exec "$CONTAINER" test -f "$BUILDALL_DIR/buildstatus.txt"; then
	docker cp "$CONTAINER:$BUILDALL_DIR/buildstatus.txt" "$STAGE/build-all/"
else
	: >"$STAGE/build-all/buildstatus.txt"
fi

if compgen -G "$REPO_DIR/output/*.deb" >/dev/null; then
	cp "$REPO_DIR"/output/*.deb "$STAGE/output/"
fi

if [ "$WITH_LOGS" = true ]; then
	mkdir -p "$STAGE/logs"
	docker exec "$CONTAINER" sh -c "cd '$BUILDALL_DIR' && tar -cf - *.out" \
		| tar -C "$STAGE/logs" -xf - 2>/dev/null || true
fi

if [ "$WITH_CACHE" = true ]; then
	mkdir -p "$STAGE/cache"
	docker exec "$CONTAINER" tar -C /home/builder/.termux-build -cf - \
		_cache/android-gcc-cross _cache/android-r30-api-30-v0 \
		| tar -C "$STAGE/cache" -xf -
fi

if [ -n "$OUTPUT" ]; then
	OUT="$OUTPUT"
else
	OUT="$PWD/termux-build-backup_${ARCH}_$(date +%Y%m%d-%H%M).tar.xz"
fi

XZ_LEVEL=6
if [ "$WITH_CACHE" = true ]; then
	XZ_LEVEL=1
fi

{
	echo "Termux GCC toolchain build backup (arch: $ARCH)"
	echo "Generated: $(date -u)"
	echo ""
	echo "Contents:"
	echo "  build-all/buildorder.txt   full build order used by build-all.sh"
	echo "  build-all/buildstatus.txt  names of already built packages, one per line"
	echo "  output/*.deb               built package artifacts"
	if [ "$WITH_LOGS" = true ]; then
		echo "  logs/*.out                 per-package build logs"
	fi
	if [ "$WITH_CACHE" = true ]; then
		echo "  cache/_cache/*             android-gcc-cross + android-r30-api-30-v0 toolchains"
	fi
	echo ""
	echo "Restore on a fresh machine:"
	echo "  1. Clone the termux-packages fork and check out the gcc-cross-toolchain branch."
	echo "  2. Start the build container: ./scripts/run-docker.sh bash"
	echo "  3. Inside the container:"
	echo "       mkdir -p ~/.termux-build/_buildall-$ARCH"
	echo "       cp <backup>/build-all/* ~/.termux-build/_buildall-$ARCH/"
	echo "     Copy <backup>/output/*.deb into the output/ directory of the repo clone."
	if [ "$WITH_CACHE" = true ]; then
		echo "       cp -a <backup>/cache/_cache/. ~/.termux-build/_cache/"
	fi
	echo "  4. Resume the build:"
	echo "       nohup ./build-all.sh > /tmp/buildall-nohup.log 2>&1 &"
	echo "     build-all.sh prints 'Continuing build-all from: ...' and skips"
	echo "     every package already listed in buildstatus.txt."
} >"$STAGE/README.txt"

TAR_ARGS=(build-all output README.txt)
[ "$WITH_LOGS" = true ] && TAR_ARGS+=(logs)
[ "$WITH_CACHE" = true ] && TAR_ARGS+=(cache)

echo "Creating $OUT (xz level $XZ_LEVEL, this may take a while)..."
tar -C "$STAGE" -cf - "${TAR_ARGS[@]}" \
	| xz -T "${XZ_THREADS:-0}" "-${XZ_LEVEL}" >"$OUT"

echo "Wrote $OUT ($(du -h "$OUT" | cut -f1), $(tar -tf "$OUT" | wc -l) files)"
sha256sum "$OUT"
