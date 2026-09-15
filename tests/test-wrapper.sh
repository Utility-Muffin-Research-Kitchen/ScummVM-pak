#!/bin/sh
# Checks for pak/emulators/scummvm-standalone/launch-game.sh, run in dry-run
# mode so no ScummVM binary is needed.
#
#   sh tests/test-wrapper.sh
#
# The descriptor cases mirror Jawaka's internal/scrape/scrape_identity_test.c,
# so the wrapper launches exactly the files the library accepts. POSIX sh only,
# so the same file runs on a host and on an MLP1 (BusyBox grep/sed).
set -eu

REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WRAPPER="${WRAPPER:-$REPO_ROOT/pak/emulators/scummvm-standalone/launch-game.sh}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/scummvm-wrapper.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

failures=0
checks=0
pass() { checks=$((checks + 1)); }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); echo "FAIL $*"; }

# A fake installed pak so the wrapper finds its defaults, with a stand-in
# scummvm that answers --detect the way ScummVM prints it: the game ID from the
# descriptor beside the game, qualified with engine "fakeengine". A game ID of
# "nodetect" finds nothing.
PAK="$TMP/ScummVM.pak/emulators/scummvm-standalone"
mkdir -p "$PAK/defaults" "$PAK/bin"
cp "$WRAPPER" "$PAK/launch-game.sh"
printf '[scummvm]\ngui_theme=scummmodern\n' >"$PAK/defaults/scummvm.ini"
cat >"$PAK/bin/scummvm" <<'FAKE'
#!/bin/sh
TAB="$(printf '\t')"
CR="$(printf '\r')"
path=
for arg in "$@"; do
    case "$arg" in --path=*) path="${arg#--path=}" ;; esac
done
for f in "$path"/*.scummvm "$path"/*.svm; do
    [ -f "$f" ] || continue
    id="$(head -n 1 "$f" | sed -e "s/$CR\$//" -e "s/^[ $TAB]*//" -e "s/[ $TAB]*\$//")"
    id="${id#*:}"
    [ "$id" = nodetect ] && exit 0
    printf 'GameID                         Description   Full Path\n'
    printf -- '------------------------------ ------------- ---------\n'
    printf '%-30s %-13s %s\n' "fakeengine:$id" "Fake game" "$path"
    exit 0
done
FAKE
chmod 755 "$PAK/bin/scummvm"

CARD="$TMP/card"
export ROMS_PATH="$CARD/Roms" SAVES_PATH="$CARD/Saves"
export USERDATA_PATH="$TMP/userdata" LOGS_PATH="$TMP/logs"
export SCUMMVM_STANDALONE_DRY_RUN=1
ROOT="$ROMS_PATH/SCUMMVM"
INI="$USERDATA_PATH/scummvm-standalone/scummvm.ini"
mkdir -p "$ROOT"

# write_bytes FILE PRINTF-FORMAT: octal escapes allowed, so NUL works too.
write_bytes() { printf "$2" >"$1"; }

run() { sh "$PAK/launch-game.sh" "$@"; }

target_of() { run "$1" 2>/dev/null | tail -n 1; }

expect_valid() {  # name format expected-gameid [expected-engineid]
    dir="$ROOT/valid-$1"; mkdir -p "$dir"; desc="$dir/Game.scummvm"
    write_bytes "$desc" "$2"
    if out="$(run "$desc" 2>&1)"; then
        target="$(printf '%s\n' "$out" | tail -n 1)"
        section="$(awk -v s="[$target]" '$0==s{f=1;next} /^\[/{f=0} f' "$INI")"
        if printf '%s\n' "$section" | grep -Fxq "gameid=$3" &&
           { [ -z "${4:-}" ] || printf '%s\n' "$section" | grep -Fxq "engineid=$4"; }; then
            pass
        else
            fail "$1: target section is wrong: $section"
        fi
    else
        fail "$1: rejected a valid descriptor: $out"
    fi
}

expect_invalid() {  # name format
    dir="$ROOT/invalid-$1"; mkdir -p "$dir"; desc="$dir/Game.svm"
    write_bytes "$desc" "$2"
    if out="$(run "$desc" 2>&1)"; then
        fail "$1: accepted an invalid descriptor"
    else
        pass
    fi
}

# Valid (scrape_identity_test.c), plus an engine-qualified ID.
expect_valid lf 'kq1\n' kq1 fakeengine
expect_valid crlf-padded '\t kq1 \t\r\n' kq1 fakeengine
expect_valid no-newline 'kq1' kq1 fakeengine
expect_valid trailing-blank-lines 'kq1\n\n \t\r\n' kq1 fakeengine
expect_valid qualified 'scumm:monkey\n' monkey scumm

# An unqualified ID ScummVM cannot detect is refused, and no target is left
# behind for it.
mkdir -p "$ROOT/Undetectable"; printf 'nodetect\n' >"$ROOT/Undetectable/Game.scummvm"
if run "$ROOT/Undetectable/Game.scummvm" 2>/dev/null; then
    fail "undetectable game accepted"
elif grep -q '^gameid=nodetect$' "$INI"; then
    fail "undetectable game left a target"
else
    pass
fi

# Invalid (scrape_identity_test.c).
expect_invalid empty ''
expect_invalid blank ' \t\n'
expect_invalid slash 'bad/path\n'
expect_invalid backslash 'bad\\path\n'
expect_invalid second-line 'kq1\nsecond\n'
expect_invalid control 'kq1\001\n'
expect_invalid bare-cr '\r'
expect_invalid leading-underscore '_kq1\n'
expect_invalid nul 'kq1\000\n'
expect_invalid high-byte 'kq1\351\n'
expect_invalid inner-cr 'kq\r1\n'
long="$(printf '%0257d' 0 | tr 0 a)"
expect_invalid too-long "$long"
expect_invalid two-colons 'a:b:c\n'

# Argument handling.
if run 2>/dev/null; then fail "no argument accepted"; else pass; fi
if run "relative/Game.scummvm" 2>/dev/null; then fail "relative path accepted"; else pass; fi

# A game outside Roms/SCUMMVM is refused rather than given an invented key.
mkdir -p "$TMP/elsewhere"; printf 'kq1\n' >"$TMP/elsewhere/Game.scummvm"
if run "$TMP/elsewhere/Game.scummvm" 2>/dev/null; then fail "game outside the ROM root accepted"; else pass; fi

# Relaunching a qualified ID reuses one target instead of adding domains.
mkdir -p "$ROOT/Monkey Island"; desc="$ROOT/Monkey Island/Monkey Island.scummvm"
printf 'scumm:monkey\n' >"$desc"
first="$(target_of "$desc")"
for _ in 1 2 3 4; do target_of "$desc" >/dev/null; done
count="$(grep -c "^\[$first\]\$" "$INI")"
[ "$count" -eq 1 ] && pass || fail "relaunch left $count copies of [$first]"

# Two editions with the same ID get separate targets and save folders.
mkdir -p "$ROOT/DOTT CD" "$ROOT/DOTT Floppy"
printf 'tentacle\n' >"$ROOT/DOTT CD/DOTT.scummvm"
printf 'tentacle\n' >"$ROOT/DOTT Floppy/DOTT.scummvm"
cd_target="$(target_of "$ROOT/DOTT CD/DOTT.scummvm")"
floppy_target="$(target_of "$ROOT/DOTT Floppy/DOTT.scummvm")"
[ -n "$cd_target" ] && [ "$cd_target" != "$floppy_target" ] && pass ||
    fail "two editions share target $cd_target"
save_arg="$(run "$ROOT/DOTT CD/DOTT.scummvm" | grep '^--savepath=')"
[ "$save_arg" = "--savepath=$SAVES_PATH/ScummVM-Standalone/$cd_target" ] && pass ||
    fail "save folder is $save_arg"

# The same card under another mount spelling keeps the same target.
ln -s "$CARD" "$TMP/card-alias"
alias_target="$(ROMS_PATH="$TMP/card-alias/Roms" sh "$PAK/launch-game.sh" \
    "$TMP/card-alias/Roms/SCUMMVM/Monkey Island/Monkey Island.scummvm" | tail -n 1)"
[ "$alias_target" = "$first" ] && pass || fail "mount alias changed target: $alias_target vs $first"

# Launch arguments carry the physical game folder and the target name last.
args="$(run "$desc")"
printf '%s\n' "$args" | grep -Fxq -- "--path=$(CDPATH= cd -- "$ROOT/Monkey Island" && pwd -P)" && pass ||
    fail "missing --path for the game folder: $args"
printf '%s\n' "$args" | grep -Fxq -- "--config=$INI" && pass || fail "missing --config"

# The built-in pad is named by its printed labels: A is button 1, B button 0.
printf '%s\n' "$args" | grep -q '^SDL_GAMECONTROLLERCONFIG=19000000039900001399000002010000,Loong Gamepad,a:b1,b:b0,x:b3,y:b2,' &&
    pass || fail "missing label-correct pad mapping: $args"

# A target whose recorded game differs is refused, not shared.
sed "s|^leaf_rom=Monkey Island/Monkey Island.scummvm\$|leaf_rom=Other/Game.scummvm|" "$INI" >"$INI.new"
mv "$INI.new" "$INI"
if run "$desc" 2>/dev/null; then fail "target of another game reused"; else pass; fi

# The seed never overwrites a config ScummVM has written.
printf '[scummvm]\nmusic_volume=42\n' >"$INI"
run "$ROOT/valid-lf/Game.scummvm" >/dev/null
grep -Fxq "music_volume=42" "$INI" && pass || fail "existing config was overwritten"

echo "test-wrapper: $((checks - failures))/$checks passed"
[ "$failures" -eq 0 ]
