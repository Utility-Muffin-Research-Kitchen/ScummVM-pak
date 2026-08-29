# ScummVM content pak

Adds a **ScummVM system** to a Leaf device — its own console tile, its own
`Roms/SCUMMVM` folder, its own box art — and ships the libretro core that runs
it. It touches nothing that Leaf manages, and uninstalling it is deleting one
directory.

It is also the **reference content pak**. If you are building your own, clone
this repository and change the parts that are yours. Everything here is
deliberately self-contained: a clean clone plus Docker, `make`, and `python3`
is the entire toolchain. There are no sibling checkouts, no UMRK workspace
layout, and no locally built images. If you find a `../` in the build system,
that is a bug — CI fails on it.

```bash
git clone https://github.com/Utility-Muffin-Research-Kitchen/ScummVM-pak
cd ScummVM-pak
make validate      # fast: check the manifest against the contract
make dist-pakrat   # long:  build the core, package, hash
```

## What a content pak is

An ordinary `.pak` whose `pak.json` carries a top-level `provides` block. That
block is the whole mechanism — it declares systems and the cores that run
them, and Leaf merges it into an *effective catalog* at scan time.

This one is the **pure** case: it has **no `launch.sh`**, so it is not listed
in Apps and there is nothing to open. Installing it makes a console tile
appear, not an app. A pak that has both a `launch.sh` and a `provides` block
is a hybrid; it gets listed in Apps *and* contributes content.

## Layout

```text
pakrat.json                     store submission metadata; kind: content
Makefile                        core / package-mlp1 / dist-pakrat / dist-source / validate
core/
  core.lock.json                pinned source commit, deps, toolchain digest, artifact sha256
  build-core.sh                 self-contained build; refuses a hash mismatch
  leaf.patch                    bundled-data lookup + handheld defaults
  PROVENANCE.md                 what was built, from what, with which flags
LICENSES/                       GPLv3 for the core; MIT and asset licence notes
pak/
  pak.json                      provides.systems[SCUMMVM] + provides.cores[scummvm]
  art/SCUMMVM.png               256px libretro Systematic flat icon
  art/SCUMMVM-photo.png         384px photographic launcher icon
scripts/
  validate-pak.py               validates against the CONTRACT's own reference validator
```

`pak/cores/` and `pak/info/` are **not** in the repository. The pinned
upstream build supplies the core, canonical `.info`, themes, engine data,
virtual keyboard, shaders, and soundfont under `build/package/ScummVM.pak`.
The data remains beside the core; `BIOS/scummvm.ini` stays user-owned. A
committed binary is a binary nobody can check against its source.

## Putting games in it

```text
Roms/SCUMMVM/
  Beneath a Steel Sky/
    beneath.scummvm          <- a game-ID hook, one line
    ... the game's own files ...
```

The `.scummvm` file contains **only the ScummVM game identifier**, e.g.:

```
sky
```

The core infers the game's location from where the hook file sits, so the hook
must live in the same directory as the game data. That matters more than it
looks: the alternative — a target-mode hook naming a path inside
`scummvm.ini` — breaks on this hardware, because the SD card mounts at
`/mnt/sdcard` or `/media/sdcard1` and **the two swap across reboots**. A hook
that names an absolute path works until the next boot.

No game data is distributed here. Bring your own.

## Building your own content pak from this one

1. Copy the repository. Replace `pak/pak.json`'s `provides` block with your
   system and core, and `pakrat.json` with your store metadata.
2. Keep `kind: "content"` in `pakrat.json`. A pak that declares `provides`
   belongs in the storefront's `content[]` lane; the generator rejects it in
   `apps[]`.
3. Repoint `core/core.lock.json` at your core's upstream and toolchain. Record
   a real `artifact.sha256` after your first verified build — until you do,
   the build refuses to claim it verified anything.
4. Run `make validate` early and often. It uses the contract's own validator,
   so a rejection you see locally is exactly what the store will say.
5. Read the licence of whatever you are shipping. If it is GPL, `make
   dist-source` exists for a reason.

### Things the contract will refuse

Worth knowing before you spend a build on them:

- Claiming an existing system's id, ROM folder, image folder, or match
  pattern. Additions are additive; collisions refuse **both** sides.
- Overriding a first-party system's default core. Use `system_extensions[]` to
  *add* an alternate core instead.
- `requires_direct_drm`, `legacy_flat_core`, `name_map`, `status`. These are
  release-owned; a third-party claim to any of them is rejected outright.
- Absolute paths anywhere in `provides`. See the mount-swap note above.
- `platform: "shared"`. Cores are platform-specific.

## Verifying the core you ship

`core/build-core.sh` clones the pinned commit, verifies and applies
`core/leaf.patch`, then builds it in a digest-pinned toolchain image and
compares the result against `core.lock.json`. A mismatch
fails the build rather than packaging whatever happened to be produced —
because "the core changed and nobody noticed" is exactly the failure this
repository is meant to make impossible.

Reproduce the build before you trust the hash. One build agreeing with itself
proves nothing.
