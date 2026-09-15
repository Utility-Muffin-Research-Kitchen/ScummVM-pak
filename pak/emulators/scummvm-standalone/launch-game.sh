#!/bin/sh
# Leaf launch wrapper for the standalone ScummVM.
#
# This is the part of the pak to copy when you add your own standalone
# emulator. Leaf runs it with one argument, the absolute path of the game the
# user selected, and the public runtime environment (SDCARD_PATH, ROMS_PATH,
# SAVES_PATH, USERDATA_PATH, LOGS_PATH, ...). The wrapper turns that into an
# emulator command line and replaces itself with the emulator (`exec`), so
# Leaf supervises the emulator directly and sees its exit status.
#
# For ScummVM the selected file is a descriptor holding one game ID:
#
#   Roms/SCUMMVM/Beneath a Steel Sky/
#     Beneath a Steel Sky.scummvm     contains: sky
#     ... game data ...
#
# Set SCUMMVM_STANDALONE_DRY_RUN=1 to print the command line, one argument per
# line, instead of starting ScummVM. The tests use it.
set -eu

SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BIN="$SELF_DIR/bin/scummvm"
SHARE="$SELF_DIR/share/scummvm"

die() {
    echo "scummvm-standalone: $*" >&2
    exit 2
}

# The launcher already exports the runtime paths; a manual run from a shell
# can pick them up from the public environment file.
if [ -z "${ROMS_PATH:-}" ] && [ -n "${SDCARD_PATH:-}" ] && [ -n "${PLATFORM:-}" ] &&
   [ -f "$SDCARD_PATH/.system/leaf/platforms/$PLATFORM/launcher/env.sh" ]; then
    . "$SDCARD_PATH/.system/leaf/platforms/$PLATFORM/launcher/env.sh"
fi

for name in ROMS_PATH SAVES_PATH USERDATA_PATH LOGS_PATH; do
    eval "value=\${$name:-}"
    [ -n "$value" ] || die "$name is not set; run this from Leaf"
done

DESC="${1:-}"
[ -n "$DESC" ] || die "no game given"
case "$DESC" in
    /*) ;;
    *) die "game path must be absolute: $DESC" ;;
esac
[ -f "$DESC" ] || die "not a file: $DESC"

# ---------------------------------------------------------------------------
# Descriptor. The rules match Leaf's scraper (Jawaka scrape_identity.c), so a
# file the library accepts is exactly a file this wrapper launches:
#   at most 256 bytes; only tab, LF, CR and printable ASCII; CR only as CRLF;
#   the identity is the first line with spaces and tabs trimmed, 1-128
#   characters, a letter or digit first, then letters, digits, _ . : -;
#   anything after the first line is whitespace.
# Only POSIX tools and options BusyBox also supports are used here.
# ---------------------------------------------------------------------------
export LC_ALL=C
CR="$(printf '\r')"
TAB="$(printf '\t')"

size="$(wc -c <"$DESC" | tr -d ' ')"
[ "$size" -le 256 ] || die "descriptor is larger than 256 bytes"

other="$(tr -d '\011\012\015\040-\176' <"$DESC" | wc -c | tr -d ' ')"
[ "$other" -eq 0 ] || die "descriptor contains bytes other than printable ASCII"

# A CR must be followed by LF: after removing line-final CRs nothing may remain,
# and the file may not end in a bare CR.
if sed "s/$CR\$//" "$DESC" | grep -q "$CR"; then
    die "descriptor contains a CR that does not end a line"
fi
if [ "$size" -gt 0 ] && [ "$(tail -c 1 "$DESC")" = "$CR" ]; then
    die "descriptor ends with a bare CR"
fi

first="$(head -n 1 "$DESC" | sed -e "s/$CR\$//" -e "s/^[ $TAB]*//" -e "s/[ $TAB]*\$//")"
rest="$(tail -n +2 "$DESC" | tr -d " \011\012\015" | wc -c | tr -d ' ')"
[ "$rest" -eq 0 ] || die "descriptor has more than one line"

GAME_ID="$first"
[ -n "$GAME_ID" ] || die "descriptor is empty"
[ "${#GAME_ID}" -le 128 ] || die "game ID is longer than 128 characters"
case "$GAME_ID" in
    [A-Za-z0-9]*) ;;
    *) die "game ID must start with a letter or digit" ;;
esac
case "$GAME_ID" in
    *[!A-Za-z0-9_.:-]*) die "game ID contains a character other than letters, digits, _ . : -" ;;
esac

case "$GAME_ID" in
    *:*) ENGINE_ID="${GAME_ID%%:*}"; SHORT_ID="${GAME_ID#*:}" ;;
    *) ENGINE_ID=""; SHORT_ID="$GAME_ID" ;;
esac
[ -n "$SHORT_ID" ] && [ -n "${ENGINE_ID:-x}" ] || die "malformed engine:game ID"
case "$SHORT_ID" in
    *:*) die "game ID has more than one ':'" ;;
esac

# ---------------------------------------------------------------------------
# Game key and ScummVM target.
#
# ScummVM keeps a game's own settings and key bindings only for a registered
# target, never for a game started by bare ID. So each game gets a target named
# from its path relative to the selected card's Roms/SCUMMVM. Physical paths
# are compared, so the same card mounted under a different directory keeps the
# same key.
# ---------------------------------------------------------------------------
ROM_ROOT="$ROMS_PATH/SCUMMVM"
[ -d "$ROM_ROOT" ] || die "no ROM folder: $ROM_ROOT"
ROM_ROOT_P="$(CDPATH= cd -- "$ROM_ROOT" && pwd -P)"
GAME_DIR="$(CDPATH= cd -- "$(dirname -- "$DESC")" && pwd -P)"
DESC_P="$GAME_DIR/$(basename -- "$DESC")"
case "$DESC_P" in
    "$ROM_ROOT_P"/*) GAME_KEY="${DESC_P#"$ROM_ROOT_P"/}" ;;
    *) die "game is not inside $ROM_ROOT" ;;
esac
case "$GAME_KEY" in
    *"$CR"*) die "game path contains a CR" ;;
esac

# cksum prints "<crc> <length>"; split it into $1 and $2 on purpose.
# shellcheck disable=SC2046
set -- $(printf '%s' "$GAME_KEY" | cksum)
TARGET="leaf-$1-$2"

CONFIG_DIR="$USERDATA_PATH/scummvm-standalone"
INI="$CONFIG_DIR/scummvm.ini"
SAVE_DIR="$SAVES_PATH/ScummVM-Standalone/$TARGET"
LOG_FILE="$LOGS_PATH/scummvm-standalone.log"
mkdir -p "$CONFIG_DIR" "$SAVE_DIR" "$LOGS_PATH" || die "could not create state folders"

# First run only: seed the global config. Never overwritten afterwards.
if [ ! -f "$INI" ]; then
    cp "$SELF_DIR/defaults/scummvm.ini" "$INI" || die "could not seed $INI"
fi

# The value ScummVM would read for KEY inside [SECTION], with surrounding
# whitespace trimmed the way ScummVM trims it.
ini_value() {
    awk -v section="[$1]" -v key="$2" '
        { line = $0; sub(/\r$/, "", line) }
        line ~ /^\[/ { in_section = (line == section); next }
        in_section {
            eq = index(line, "=")
            if (eq == 0) next
            k = substr(line, 1, eq - 1); v = substr(line, eq + 1)
            gsub(/^[ \t]+|[ \t]+$/, "", k); gsub(/^[ \t]+|[ \t]+$/, "", v)
            if (k == key) { print v; exit }
        }' "$INI"
}

trimmed_key="$(printf '%s' "$GAME_KEY" | sed -e "s/^[ $TAB]*//" -e "s/[ $TAB]*\$//")"
if grep -Fxq "[$TARGET]" "$INI"; then
    [ "$(ini_value "$TARGET" leaf_rom)" = "$trimmed_key" ] ||
        die "target $TARGET belongs to another game; edit or remove it in $INI"
else
    # A target needs its engine ID. ScummVM cannot work one out for a target
    # that stores no game path, and this wrapper never stores one, so ask
    # ScummVM's own detection once, when the game is first registered. It runs
    # against a throwaway config because --detect writes the file it is given.
    if [ -z "$ENGINE_ID" ]; then
        detect_ini="${TMPDIR:-/tmp}/scummvm-standalone-detect.$$.ini"
        ENGINE_ID="$("$BIN" --config="$detect_ini" --extrapath="$SHARE" \
            --detect --path="$GAME_DIR" 2>/dev/null |
            awk -v id="$SHORT_ID" 'index($1, ":") {
                engine = substr($1, 1, index($1, ":") - 1)
                game = substr($1, index($1, ":") + 1)
                if (game == id) { print engine; exit }
            }')" || true
        rm -f "$detect_ini"
        [ -n "$ENGINE_ID" ] || die "ScummVM found no game '$SHORT_ID' in $GAME_DIR"
    fi
    # ScummVM is not running (Leaf starts one game at a time), so appending is
    # safe; content ScummVM wrote is never rewritten here.
    {
        printf '\n[%s]\n' "$TARGET"
        printf 'gameid=%s\n' "$SHORT_ID"
        [ -z "$ENGINE_ID" ] || printf 'engineid=%s\n' "$ENGINE_ID"
        printf 'leaf_rom=%s\n' "$GAME_KEY"
    } >>"$INI" || die "could not register $TARGET in $INI"
fi

# Controls. SDL's built-in mapping for the MLP1's pad reads the bottom face
# button as A and the right one as B, but the pad is labelled Nintendo-style,
# so ScummVM's "A" would land on the button printed B. Name the built-in pad's
# buttons by their printed labels: A is BTN_EAST (button 1), B is BTN_SOUTH
# (0), X is BTN_NORTH (2), Y is BTN_WEST (3). The GUID leaves out SDL's name
# checksum, so it matches the raw pad and Leaf's calibrated copy of it; other
# controllers keep SDL's own mappings, which follow later in the variable.
MLP1_PAD="19000000039900001399000002010000,Loong Gamepad,a:b1,b:b0,x:b2,y:b3,back:b8,start:b9,guide:b10,leftshoulder:b4,rightshoulder:b5,lefttrigger:b6,righttrigger:b7,leftstick:b11,leftx:a0,lefty:a1,dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,platform:Linux,"
SDL_GAMECONTROLLERCONFIG="$MLP1_PAD${SDL_GAMECONTROLLERCONFIG:+
$SDL_GAMECONTROLLERCONFIG}"
export SDL_GAMECONTROLLERCONFIG

# Mount-sensitive locations are passed on every launch and never stored in the
# target, so a card that moves mount point still works.
if [ "${SCUMMVM_STANDALONE_DRY_RUN:-0}" = "1" ]; then
    printf 'SDL_GAMECONTROLLERCONFIG=%s\n' "$MLP1_PAD"
    for arg in "$BIN" --fullscreen "--config=$INI" "--extrapath=$SHARE" \
        "--themepath=$SHARE" "--savepath=$SAVE_DIR" "--logfile=$LOG_FILE" \
        "--path=$GAME_DIR" "$TARGET"; do
        printf '%s\n' "$arg"
    done
    exit 0
fi

exec "$BIN" \
    --fullscreen \
    --config="$INI" \
    --extrapath="$SHARE" \
    --themepath="$SHARE" \
    --savepath="$SAVE_DIR" \
    --logfile="$LOG_FILE" \
    --path="$GAME_DIR" \
    "$TARGET"
