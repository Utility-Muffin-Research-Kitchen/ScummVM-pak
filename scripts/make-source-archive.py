#!/usr/bin/env python3
"""Create the GPL corresponding-source archive from the exact locked trees."""
from __future__ import annotations

import argparse
import gzip
import io
import json
from pathlib import Path
import subprocess
import tarfile


def git_head(repo: Path) -> str:
    return subprocess.check_output(
        ["git", "-C", str(repo), "rev-parse", "HEAD"], text=True
    ).strip()


def add_git_archive(output: tarfile.TarFile, repo: Path, commit: str,
                    prefix: str) -> None:
    process = subprocess.Popen(
        ["git", "-C", str(repo), "archive", "--format=tar", commit],
        stdout=subprocess.PIPE,
    )
    assert process.stdout is not None
    with tarfile.open(fileobj=process.stdout, mode="r|") as source:
        for member in source:
            member.name = prefix + member.name
            fileobj = source.extractfile(member) if member.isfile() else None
            output.addfile(member, fileobj)
    if process.wait() != 0:
        raise SystemExit(f"git archive failed for {repo}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", required=True, type=Path)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    lock = json.loads(args.lock.read_text(encoding="utf-8"))
    core_commit = lock["core"]["source_commit"]
    deps_root = args.source / "backends/platform/libretro/deps"
    trees = [(args.source, core_commit, f"scummvm-{core_commit}/")]
    for dependency in lock["build_dependencies"]:
        name = dependency["name"]
        commit = dependency["commit"]
        trees.append((
            deps_root / name,
            commit,
            f"scummvm-{core_commit}/backends/platform/libretro/deps/{name}/",
        ))

    for repo, commit, _ in trees:
        if not (repo / ".git").exists():
            raise SystemExit(f"missing source checkout: {repo}; run 'make core' first")
        actual = git_head(repo)
        if actual != commit:
            raise SystemExit(f"source checkout {repo} is {actual}, lock requires {commit}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w|") as output:
                for repo, commit, prefix in trees:
                    add_git_archive(output, repo, commit, prefix)

                lock_bytes = args.lock.read_bytes()
                info = tarfile.TarInfo(f"scummvm-{core_commit}/leaf-core.lock.json")
                info.size = len(lock_bytes)
                info.mode = 0o644
                info.mtime = 0
                output.addfile(info, io.BytesIO(lock_bytes))


if __name__ == "__main__":
    main()
