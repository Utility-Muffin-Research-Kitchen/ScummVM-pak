#!/usr/bin/env python3
"""Produce the core's .info file for the pak.

RetroArch reads .info files from one merged directory, and Leaf materializes
the pak's into the effective catalog. Preferring the file that ships with the
pinned source keeps it describing the core that was actually built; a
hand-written one drifts the moment the pin moves.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def find_upstream_info(source: Path) -> Path | None:
    for candidate in (
        source / "backends" / "platform" / "libretro" / "scummvm_libretro.info",
        source / "backends" / "platform" / "libretro" / "info" / "scummvm_libretro.info",
    ):
        if candidate.is_file():
            return candidate
    matches = sorted(source.rglob("scummvm_libretro.info"))
    return matches[0] if matches else None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--lock", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    lock = json.loads(args.lock.read_text())
    commit = lock["core"]["source_commit"]

    upstream = find_upstream_info(args.source) if args.source.is_dir() else None
    args.out.parent.mkdir(parents=True, exist_ok=True)

    if upstream is not None:
        text = upstream.read_text(encoding="utf-8", errors="replace").rstrip("\n")
        args.out.write_text(
            text + f'\n# packaged by ScummVM-pak from {commit}\n', encoding="utf-8"
        )
        print(f"make-core-info: from upstream {upstream.name}")
        return 0

    # Upstream did not ship one at this pin. Write the minimum RetroArch reads,
    # and say where it came from so nobody mistakes it for upstream's.
    args.out.write_text(
        "\n".join([
            'display_name = "ScummVM"',
            'authors = "ScummVM Team"',
            'supported_extensions = "scummvm|svm"',
            'corename = "ScummVM"',
            'license = "GPLv3"',
            'permissions = ""',
            'display_version = "%s"' % commit[:12],
            'categories = "Game engine"',
            'database = "ScummVM"',
            'is_experimental = "false"',
            f'# written by ScummVM-pak: upstream shipped no .info at {commit}',
            "",
        ]),
        encoding="utf-8",
    )
    print("make-core-info: upstream shipped none; wrote a minimal descriptor")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
