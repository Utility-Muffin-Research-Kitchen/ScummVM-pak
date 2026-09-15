#!/usr/bin/env bash
# Build the standalone ScummVM executable for the Miniloong Pocket 1.
#
# Self-contained on purpose. A clean clone of THIS repository plus Docker is
# the entire toolchain: no sibling checkouts, no UMRK workspace layout, no
# locally built images. Everything it needs is pinned in
# standalone/standalone.lock.json.
#
#   ./standalone/build-standalone.sh              build into build/, verify the lock
#   FORCE=1 ./standalone/build-standalone.sh      rebuild everything from clean trees
#
# Source archives, the ScummVM clone and the codec build tree are cached under
# build/ so a second run is cheap.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$REPO_ROOT/standalone/standalone.lock.json"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"
SRC_DIR="$BUILD_DIR/scummvm-standalone-src"
DOWNLOADS="$BUILD_DIR/downloads"
WORK_DIR="$BUILD_DIR/standalone-work"
OUT_DIR="$BUILD_DIR/standalone"

die() { echo "build-standalone: $*" >&2; exit 1; }
say() { echo "build-standalone: $*"; }

command -v docker >/dev/null 2>&1 || die "docker is required"
command -v git >/dev/null 2>&1 || die "git is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required"
command -v curl >/dev/null 2>&1 || die "curl is required"

# lock KEY [KEY...] prints one value from the lock; list indices are numbers.
lock() {
  python3 - "$LOCK" "$@" <<'PY'
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
for key in sys.argv[2:]:
    value = value[int(key)] if isinstance(value, list) else value[key]
print(json.dumps(value) if isinstance(value, (dict, list)) else value)
PY
}

sha256() {
  python3 - "$1" <<'PY'
import hashlib, sys
print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())
PY
}

SOURCE_URL="$(lock core source_url)"
SOURCE_COMMIT="$(lock core source_commit)"
IMAGE="$(lock toolchain image)"
DIGEST="$(lock toolchain digest)"
CROSS="$(lock toolchain cross_prefix)"
ARTIFACT="$(lock artifact file_name)"
EXPECTED_SHA="$(lock artifact sha256)"
SOURCE_EPOCH="$(lock build source_date_epoch)"
GLIBC_CEILING="$(lock device glibc_ceiling)"

# A tag can move; a digest cannot.
IMAGE_REF="${IMAGE%%:*}@${DIGEST}"

mkdir -p "$BUILD_DIR" "$DOWNLOADS" "$OUT_DIR"

# Every external input, as "file url sha256", then every in-repo patch as
# "path - sha256". Nothing is used before its hash matches the lock.
INPUTS="$(python3 - "$LOCK" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1], encoding="utf-8"))
for codec in lock["codecs"]:
    print(codec["file"], codec["url"], codec["sha256"])
    if "debian_patch" in codec:
        patch = codec["debian_patch"]
        print(patch["file"], patch["url"], patch["sha256"])
for codec in lock["codecs"]:
    for patch in codec.get("patches", []):
        print(patch["file"], "-", patch["sha256"])
PY
)"

while read -r file url expected; do
  [ -n "$file" ] || continue
  if [ "$url" = "-" ]; then
    path="$REPO_ROOT/$file"
    [ -f "$path" ] || die "missing patch: $file"
  else
    path="$DOWNLOADS/$file"
    if [ ! -f "$path" ]; then
      say "fetching $url"
      curl -fsSL --retry 3 -o "$path.part" "$url" || die "download failed: $url"
      mv "$path.part" "$path"
    fi
  fi
  actual="$(sha256 "$path")"
  [ "$actual" = "$expected" ] || die "sha256 mismatch for $file
  got:    $actual
  locked: $expected"
done <<<"$INPUTS"
say "source archives and patches match the lock"

if [ -f "$OUT_DIR/$ARTIFACT" ] && [ "${FORCE:-0}" != "1" ]; then
  say "binary already present (FORCE=1 to rebuild)"
else
  if [ ! -d "$SRC_DIR/.git" ]; then
    say "cloning $SOURCE_URL (large; one time)"
    git init -q "$SRC_DIR"
    git -C "$SRC_DIR" remote add origin "$SOURCE_URL"
  fi
  if [ "$(git -C "$SRC_DIR" rev-parse -q --verify HEAD 2>/dev/null)" != "$SOURCE_COMMIT" ]; then
    say "fetching pinned commit $SOURCE_COMMIT"
    git -C "$SRC_DIR" fetch -q --depth 1 origin "$SOURCE_COMMIT"
    git -C "$SRC_DIR" checkout -q --detach FETCH_HEAD
  fi
  [ "$(git -C "$SRC_DIR" rev-parse HEAD)" = "$SOURCE_COMMIT" ] \
    || die "checked out $(git -C "$SRC_DIR" rev-parse HEAD), lock says $SOURCE_COMMIT"

  # ScummVM ships unpatched. Tracked files must match the commit exactly.
  git -C "$SRC_DIR" diff --quiet HEAD \
    || die "the ScummVM tree has local changes; this lane builds it unmodified"

  if [ "${FORCE:-0}" = "1" ]; then
    say "forcing a clean rebuild"
    git -C "$SRC_DIR" clean -qfdx
    rm -rf "$WORK_DIR" "$OUT_DIR"
    mkdir -p "$OUT_DIR"
  fi
  mkdir -p "$WORK_DIR"

  say "building in $IMAGE_REF"
  docker run --rm \
    -e CROSS="$CROSS" \
    -e SOURCE_DATE_EPOCH="$SOURCE_EPOCH" \
    -e GLIBC_CEILING="$GLIBC_CEILING" \
    -e ARTIFACT="$ARTIFACT" \
    -v "$SRC_DIR":/src \
    -v "$WORK_DIR":/work \
    -v "$OUT_DIR":/out \
    -v "$DOWNLOADS":/downloads:ro \
    -v "$REPO_ROOT/standalone":/standalone:ro \
    -w /src \
    "$IMAGE_REF" \
    bash /standalone/build-in-container.sh
fi

[ -f "$OUT_DIR/$ARTIFACT" ] || die "build produced no $ARTIFACT"
[ -d "$OUT_DIR/share/scummvm" ] || die "build staged no share/scummvm data"

ACTUAL_SHA="$(sha256 "$OUT_DIR/$ARTIFACT")"
SIZE_BYTES="$(python3 -c 'import os,sys;print(os.path.getsize(sys.argv[1]))' "$OUT_DIR/$ARTIFACT")"
say "artifact sha256 $ACTUAL_SHA ($SIZE_BYTES bytes)"

if [ "$EXPECTED_SHA" = "PENDING-FIRST-VERIFIED-BUILD" ]; then
  echo
  say "standalone.lock.json has no recorded artifact hash yet."
  say "Reproduce this build with FORCE=1, confirm the same hash, then record it"
  say "under artifact.sha256 and artifact.size_bytes."
  exit 0
fi

[ "$ACTUAL_SHA" = "$EXPECTED_SHA" ] \
  || die "artifact sha256 mismatch
  built:  $ACTUAL_SHA
  locked: $EXPECTED_SHA
A mismatch means a source, a patch, or the toolchain moved. Do not update the
lock without knowing which."

say "matches the lock"
