#!/usr/bin/env bash
# Build the ScummVM libretro core for the Miniloong Pocket 1.
#
# Self-contained on purpose. A clean clone of THIS repository plus Docker is
# the entire toolchain: no sibling checkouts, no UMRK workspace layout, no
# locally built images. Everything it needs is pinned in core/core.lock.json.
#
#   ./core/build-core.sh              build into build/, verify against the lock
#   FORCE=1 ./core/build-core.sh      rebuild even if the artifact is present
#
# The source clone is large (~800 MB) and the build is long. Both are cached
# under build/ so a second run is cheap.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$REPO_ROOT/core/core.lock.json"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"
SRC_DIR="$BUILD_DIR/scummvm-src"
OUT_DIR="$BUILD_DIR/core"

die() { echo "build-core: $*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "docker is required"
command -v git >/dev/null 2>&1 || die "git is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required"

lock_get() {
  python3 -c "import json,sys;d=json.load(open('$LOCK'));print(eval('d'+sys.argv[1]))" "$1"
}

SOURCE_URL="$(lock_get "['core']['source_url']")"
SOURCE_COMMIT="$(lock_get "['core']['source_commit']")"
IMAGE="$(lock_get "['toolchain']['image']")"
DIGEST="$(lock_get "['toolchain']['digest']")"
CROSS="$(lock_get "['toolchain']['cross_prefix']")"
ARTIFACT="$(lock_get "['artifact']['file_name']")"
EXPECTED_SHA="$(lock_get "['artifact']['sha256']")"

# A tag can move; a digest cannot. Prefer the digest when the lock has one, so
# two people building months apart get the same compiler.
IMAGE_REF="$IMAGE"
if [ -n "$DIGEST" ] && [ "$DIGEST" != "null" ]; then
  IMAGE_REF="${IMAGE%%:*}@${DIGEST}"
fi

mkdir -p "$BUILD_DIR" "$OUT_DIR"

if [ -f "$OUT_DIR/$ARTIFACT" ] && [ "${FORCE:-0}" != "1" ]; then
  echo "build-core: $OUT_DIR/$ARTIFACT already present (FORCE=1 to rebuild)"
else
  if [ ! -d "$SRC_DIR/.git" ]; then
    echo "build-core: cloning $SOURCE_URL (large; one time)"
    git init -q "$SRC_DIR"
    git -C "$SRC_DIR" remote add origin "$SOURCE_URL"
  fi
  echo "build-core: fetching pinned commit $SOURCE_COMMIT"
  git -C "$SRC_DIR" fetch -q --depth 1 origin "$SOURCE_COMMIT"
  git -C "$SRC_DIR" checkout -q FETCH_HEAD

  ACTUAL_COMMIT="$(git -C "$SRC_DIR" rev-parse HEAD)"
  [ "$ACTUAL_COMMIT" = "$SOURCE_COMMIT" ] \
    || die "checked out $ACTUAL_COMMIT, lock says $SOURCE_COMMIT"

  echo "build-core: building in $IMAGE_REF"
  docker run --rm \
    -v "$SRC_DIR":/src \
    -v "$OUT_DIR":/out \
    -w /src/backends/platform/libretro \
    "$IMAGE_REF" \
    /bin/sh -euc '
      TC=/opt/mlp1-toolchain/bin/'"$CROSS"'
      # AR carries its operation letters in the variable upstream ("ar cru"),
      # so overriding it with a bare binary produces "ar <lib> <objs>" -- no
      # operation, and the archive step dies with a usage message thousands of
      # objects into the build. Keep the flags.
      make platform=unix \
        CC="${TC}-gcc" CXX="${TC}-g++" \
        AR="${TC}-ar cru" RANLIB="${TC}-ranlib" STRIP="${TC}-strip" \
        NO_WIP=1 -j"$(nproc)"
      cp '"$ARTIFACT"' /out/
      "${TC}-strip" --strip-unneeded /out/'"$ARTIFACT"'
    '
fi

[ -f "$OUT_DIR/$ARTIFACT" ] || die "build produced no $ARTIFACT"

ACTUAL_SHA="$(python3 - "$OUT_DIR/$ARTIFACT" <<'PY'
import hashlib, sys
print(hashlib.sha256(open(sys.argv[1], 'rb').read()).hexdigest())
PY
)"
echo "build-core: artifact sha256 $ACTUAL_SHA"

if [ "$EXPECTED_SHA" = "PENDING-FIRST-VERIFIED-BUILD" ]; then
  echo
  echo "build-core: core.lock.json has no recorded hash yet."
  echo "            Reproduce this build, confirm you get the same hash, then put"
  echo "            it in core/core.lock.json under artifact.sha256."
  exit 0
fi

[ "$ACTUAL_SHA" = "$EXPECTED_SHA" ] \
  || die "artifact sha256 mismatch
  built:  $ACTUAL_SHA
  locked: $EXPECTED_SHA
A mismatch means the source, the dependencies, or the toolchain moved. Do not
update the lock without knowing which."

echo "build-core: matches the lock"
