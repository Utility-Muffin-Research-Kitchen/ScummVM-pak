# Core provenance

What is in `scummvm_libretro.so`, where it came from, and how to get the same
bytes again. `core/core.lock.json` is the machine-readable version of this
file and is what the build actually enforces; this one explains it.

## Source

| | |
| --- | --- |
| Upstream | `https://github.com/libretro/scummvm.git` |
| Commit | `825fea130aba5a55005c307fb22fce2445749317` |
| Licence | GPL-3.0-or-later (`COPYING` in that tree, copied to `LICENSES/CORE-LICENSE.txt`) |

`core/leaf.patch` is hash-pinned beside the upstream commit. It makes the core
prefer its packaged upstream data directories, changes the default RetroPad
mapping for handheld use, and leaves hardware rendering disabled by default on
the GLES-only MLP1 frontend. The unmodified upstream tree and this patch are
both included in the corresponding-source archive.

A branch name is not provenance. The commit is pinned because "master" is a
different program every week, and a GPLv3 corresponding-source obligation
attaches to the exact binary that was distributed.

## Build dependencies

The upstream libretro backend pins its own dependencies in
`backends/platform/libretro/dependencies.mk`, and fetches them during the
build. They are restated in `core.lock.json` so the pins are visible without
reading the source:

| Dependency | Commit |
| --- | --- |
| `libretro/libretro-deps` | `bab7d258c451c0e7cba4b6a79f1b062c13efff38` |
| `libretro/libretro-common` | `879c8d507b0b52e77e27d759239c2b5df1e26dfd` |

These are fetched over the network at build time, so a build is not fully
hermetic. That is upstream's design, not something this repository chose; the
mitigation is that the commits are exact and the resulting artifact is hashed.

## Toolchain

| | |
| --- | --- |
| Image | `ghcr.io/utility-muffin-research-kitchen/mlp1-toolchain` |
| Digest | `sha256:66aac16fb8b07e663c9b4d66970f272df195a6eba98dfad8286eabbaa617faf9` |
| Compiler | `aarch64-buildroot-linux-gnu-g++ 12.3.0` (Buildroot) |
| Target | aarch64 Cortex-A55, glibc — Miniloong Pocket 1 (RK3566) |

Pulled anonymously; no UMRK credentials and no local image build are required.
The **digest** is what the build uses, not the tag: a tag can move, and a moved
compiler produces a different binary.

## Build

```
make platform=unix \
     CC=aarch64-buildroot-linux-gnu-gcc \
     CXX=aarch64-buildroot-linux-gnu-g++ \
     AR="aarch64-buildroot-linux-gnu-ar cru" \
     RANLIB=aarch64-buildroot-linux-gnu-ranlib \
     STRIP=aarch64-buildroot-linux-gnu-strip \
     GIT_TAG= GIT_HASH=825fea13 \
     NO_WIP=1 -j$(nproc)
```

then `--strip-unneeded`, because the unstripped core is large and an SD card is
not.

The same pinned source target builds `scummvm.zip` and
`scummvm_libretro.info`. The package extracts that archive beside the core, so
themes and engine data are removed atomically with the pak instead of being
copied into the shared `BIOS` tree.

`NO_WIP=1` is upstream's default and excludes work-in-progress engines. Turning
it on would ship engines upstream does not consider ready, under this
repository's name.

`platform=unix` with an explicit cross toolchain is used rather than one of
upstream's board presets (`rpi3_64`, `rpi4_64`, …): those carry board-specific
tuning flags that are wrong for an RK3566, and being explicit is clearer than
inheriting someone else's `-mcpu`.

The eight-character `GIT_HASH` is derived from the pinned source commit and
passed explicitly. Upstream otherwise runs `git rev-parse --short` inside the
container. That produced different binaries when Git chose a longer
abbreviation from a populated local object database, and produced no hash at
all when a Linux bind mount triggered Git's ownership safety check. Neither is
a source change, so neither should be allowed to change the artifact.

`FORCE=1 make core` removes ignored and untracked products from the cached
source tree before building. Without that clean, a nominal rebuild could reuse
objects compiled with an older command line and give a false verification.

## Artifact

`core.lock.json` carries the `sha256` of the built `.so`. `build-core.sh`
compares against it and **fails** on a mismatch rather than packaging whatever
was produced.

The current hash was recorded from a clean build on 2026-08-29 after removing
the host-dependent Git revision behavior described above. CI performs the
independent build from a fresh clone; a successful main or manually dispatched
build is the second-machine verification.

### Recording a hash

1. `make core` on a clean checkout. Note the printed sha256.
2. `make distclean && make core` — ideally on another machine. Note it again.
3. If they agree, put it in `core.lock.json`. If they do not, find out why
   before recording either.

If two hashes differ, inspect every input before changing the lock. For this
core the first mismatch was not a timestamp: it was upstream's implicit Git
revision lookup changing with clone history and bind-mount ownership. The build
now supplies that value explicitly.

## Non-commercial constraints

Leaf applies its own rules about which cores may ship inside a release image.
Those are a separate matter from this pak's licence obligations and do not
discharge them. This pak is distributed on its own, through the store, not as
part of a Leaf release.
