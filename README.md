# ScummVM content pak

Adds a **ScummVM system** to a Leaf device: its own console tile, its own
`Roms/SCUMMVM` folder and its own box art. Games run on the libretro ScummVM
core by default. The pak also ships the standalone ScummVM, which you can
choose for the whole system or for a single game. It touches nothing that Leaf
manages, and uninstalling it is deleting one directory.

It is also the **reference content pak**. If you are building your own, clone
this repository and change the parts that are yours. Everything here is
deliberately self-contained: a clean clone plus Docker, `make` and `python3` is
the entire toolchain. There are no sibling checkouts, no UMRK workspace layout
and no locally built images. If you find a `../` in the build system, that is a
bug.

```bash
git clone https://github.com/Utility-Muffin-Research-Kitchen/ScummVM-pak
cd ScummVM-pak
make validate       # fast: check the manifest against the contract
make test-wrapper   # fast: check the standalone launch wrapper
make dist-pakrat    # long: build both emulators, package, hash
```

## What a content pak is

An ordinary `.pak` whose `pak.json` carries a top-level `provides` block. That
block is the whole mechanism: it declares systems and the cores that run them,
and Leaf merges it into an *effective catalog* at scan time.

This one is the **pure** case: it has **no `launch.sh`**, so it is not listed
in Apps and there is nothing to open. Installing it makes a console tile
appear, not an app. A pak that has both a `launch.sh` and a `provides` block is
a hybrid; it gets listed in Apps *and* contributes content.

## Putting games in it

```text
Roms/SCUMMVM/
  Beneath a Steel Sky/
    beneath.scummvm          <- a game-ID hook, one line
    ... the game's own files ...
```

The `.scummvm` (or `.svm`) file contains **only the ScummVM game identifier**,
for example:

```
sky
```

Leaf versions that understand `CONTENT-SCRAPE-1` use that identifier for the
ScreenScraper lookup, while keeping the human filename as the launcher title
and artwork filename. For example, `Kings Quest 1.svm` containing `kq1` is
looked up as `kq1.scummvm`, but its art still lands as
`Images/SCUMMVM/Kings Quest 1.png`. Older Leaf versions ignore the hint and
scrape by filename.

Both emulators find the game's files in the folder the hook file sits in, so
keep the hook next to the game data. Don't write a hook that names an absolute
path: on this hardware the SD cards mount at `/mnt/sdcard` or `/media/sdcard1`,
and **the two swap across reboots**.

No game data is distributed here. Bring your own.

## Choosing the standalone emulator

Games start on **ScummVM (Libretro)** unless you choose otherwise. To use the
standalone ScummVM, choose **ScummVM (Standalone)** under **Core** for the
ScummVM system, or for one game.

What changes when you do:

- **Start** opens ScummVM's own menu, where you save, load, change options and
  quit. **Select** opens the virtual keyboard.
- **Menu** asks "Return to Leaf?". Press Menu again to leave the game. Leaving
  this way doesn't save, so save from ScummVM's menu first. Leaf versions
  without the prompt leave on the first press.
- Saves and settings are separate from the libretro core's. Switching
  emulators doesn't move a save.
- ScummVM's options apply to every game, and each game's own options and key
  bindings are kept for that game.
- **Return to Launcher** in ScummVM's menu shows ScummVM's own game list. Choose
  **Quit** there, or press Menu, to go back to Leaf.

The standalone emulator needs a Leaf version that launches a system's default
core ahead of an installed alternate. On an older Leaf, games with no emulator
chosen start on the standalone instead.

## Layout

```text
pakrat.json                       store submission metadata; kind: content
Makefile                          core / standalone / package-mlp1 / dist-pakrat / dist-source / validate / test-wrapper
core/                             libretro core lane
  core.lock.json                  pinned source commit, deps, toolchain digest, artifact sha256
  build-core.sh                   self-contained build; refuses a hash mismatch
  leaf.patch                      bundled-data lookup + handheld defaults
  PROVENANCE.md                   what was built, from what, with which flags
standalone/                       standalone ScummVM lane
  standalone.lock.json            upstream commit, codec archives and patches, toolchain, artifact sha256
  build-standalone.sh             host side: fetch and hash-check inputs, run the container build
  build-in-container.sh           static codecs, then unpatched ScummVM against the device's SDL2
  verify-binary.sh                architecture, RPATH, glibc ceiling, library closure
  device-libs.txt                 shared libraries the MLP1 provides
  patches/libmad/                 libmad patches, as Buildroot applies them
  PROVENANCE.md                   what was built, from what, with which flags
LICENSES/                         licences for both binaries, their libraries and the assets
pak/
  pak.json                        provides.systems[SCUMMVM] + both cores
  emulators/scummvm-standalone/   launch wrapper and first-run defaults; binary and data are built
  art/                            system icons, wordmark, grid icon
scripts/
  validate-pak.py                 validates against the CONTRACT's own reference validator
  make-source-archive.py          GPL corresponding-source archives
tests/
  test-wrapper.sh                 launch wrapper checks; runs on a host or an MLP1
```

`pak/cores/`, `pak/info/` and the standalone binary are **not** in the
repository. The pinned builds supply them under `build/package/ScummVM.pak`. A
committed binary is a binary nobody can check against its source.

## Adding a standalone emulator to your own pak

The standalone lane is the example to copy. The pieces:

1. **Declare a path core.** In `provides.cores`, a core with `"type": "path"`
   and `"path"` pointing at your launch script, relative to the pak. List it in
   your system's `default_core` or `alternate_cores`. Leave `supports_menu` at
   `false`: Leaf's Menu button then ends your emulator, which works without
   changing the emulator.
2. **Write a launch script.** Leaf runs it with the absolute path of the chosen
   game and exports the runtime paths (`ROMS_PATH`, `SAVES_PATH`,
   `USERDATA_PATH`, `LOGS_PATH`). `ROMS_PATH` and `SAVES_PATH` belong to the card
   the game is on. Pass every location on the emulator's command line each
   time, never store a mount path, and end with `exec` so Leaf supervises the
   emulator itself. See
   [`launch-game.sh`](pak/emulators/scummvm-standalone/launch-game.sh).
3. **Validate what you read.** If your game files point at something, check
   them with the same rules the library uses, and test the script without the
   emulator (`tests/test-wrapper.sh` runs this one in dry-run mode).
4. **Build from pinned sources, unmodified if you can.** This lane builds
   upstream ScummVM without patches. It links only libraries the device
   provides (`standalone/device-libs.txt`) and links everything else
   statically from hashed source archives. `verify-binary.sh` fails the build
   if the binary needs anything else.
5. **Ship the licences and the source.** Copy each component's licence into the
   package, and publish `make dist-source` output next to the pak.

## Building your own content pak from this one

1. Copy the repository. Replace `pak/pak.json`'s `provides` block with your
   system and cores, and `pakrat.json` with your store metadata.
2. Keep `kind: "content"` in `pakrat.json`. A pak that declares `provides`
   belongs in the storefront's `content[]` lane; the generator rejects it in
   `apps[]`.
3. Repoint the locks at your sources and toolchain. Record a real
   `artifact.sha256` only after two clean builds agree; until you do, the build
   refuses to claim it verified anything.
4. Run `make validate` early and often. It uses the contract's own validator,
   so a rejection you see locally is exactly what the store will say.
5. Read the licence of whatever you are shipping. If it is GPL,
   `make dist-source` exists for a reason.

### Things the contract will refuse

Worth knowing before you spend a build on them:

- Claiming an existing system's id, ROM folder, image folder or match pattern.
  Additions are additive; collisions refuse **both** sides.
- Overriding a first-party system's default core. Use `system_extensions[]` to
  *add* an alternate core instead.
- `requires_direct_drm`, `legacy_flat_core`, `name_map`, `status`. These are
  release-owned; a third-party claim to any of them is rejected outright.
- Absolute paths anywhere in `provides`. See the mount-swap note above.
- `platform: "shared"`. Cores are platform-specific.

## Verifying the binaries you ship

`core/build-core.sh` clones its pinned commit, applies its hash-pinned patch,
builds in the digest-pinned toolchain image and compares the result against its
lock. `standalone/build-standalone.sh` does the same for upstream ScummVM, which
it builds unpatched, and checks every codec archive and patch against its lock
before using it. A mismatch fails the build rather than packaging whatever
happened to be produced.

Reproduce a build before you trust its hash. One build agreeing with itself
proves nothing.
