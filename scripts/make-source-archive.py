#!/usr/bin/env python3
"""Create the GPL corresponding-source archive from the exact locked inputs.

The libretro lock names a ScummVM fork commit, its libretro dependency commits
and one patch. The standalone lock names an upstream ScummVM commit (built
unpatched), codec source archives with their patches, and the scripts that
build them; pass --downloads so the archives come from the hash-checked cache.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile

STANDALONE_BUILD_FILES = (
    "standalone/build-standalone.sh",
    "standalone/build-in-container.sh",
    "standalone/verify-binary.sh",
    "standalone/device-libs.txt",
)


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


def add_bytes(output: tarfile.TarFile, name: str, data: bytes, mode: int = 0o644) -> None:
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = mode
    info.mtime = 0
    output.addfile(info, io.BytesIO(data))


def checked_bytes(path: Path, expected: str) -> bytes:
    if not path.is_file():
        raise SystemExit(f"missing input: {path}; run the build first")
    data = path.read_bytes()
    actual = hashlib.sha256(data).hexdigest()
    if actual != expected:
        raise SystemExit(f"sha256 mismatch for {path}: {actual}, lock requires {expected}")
    return data


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", required=True, type=Path)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--lock-name", default="leaf-core.lock.json",
                        help="file name to give the lock inside the archive")
    parser.add_argument(
        "--source-prefix",
        default=None,
        help="directory name inside the archive (default scummvm-<commit>)",
    )
    parser.add_argument(
        "--downloads",
        type=Path,
        default=None,
        help="directory holding the codec source archives named in the lock",
    )
    args = parser.parse_args()

    lock = json.loads(args.lock.read_text(encoding="utf-8"))
    core_commit = lock["core"]["source_commit"]
    repo_root = args.lock.resolve().parent.parent
    root = args.source_prefix or f"scummvm-{core_commit}"

    trees = [(args.source, core_commit, f"{root}/")]
    for dependency in lock.get("build_dependencies", []):
        name = dependency["name"]
        trees.append((
            args.source / "backends/platform/libretro/deps" / name,
            dependency["commit"],
            f"{root}/backends/platform/libretro/deps/{name}/",
        ))

    for repo, commit, _ in trees:
        if not (repo / ".git").exists():
            raise SystemExit(f"missing source checkout: {repo}; run the build first")
        actual = git_head(repo)
        if actual != commit:
            raise SystemExit(f"source checkout {repo} is {actual}, lock requires {commit}")

    codecs = lock.get("codecs", [])
    if codecs and args.downloads is None:
        raise SystemExit("this lock names codec archives; pass --downloads")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w|") as output:
                for repo, commit, tree_prefix in trees:
                    add_git_archive(output, repo, commit, tree_prefix)

                add_bytes(output, f"{root}/{args.lock_name}", args.lock.read_bytes())

                if "patch" in lock:
                    patch_file = lock["patch"]["file"]
                    add_bytes(output, f"{root}/{patch_file}",
                              (repo_root / patch_file).read_bytes())

                for codec in codecs:
                    add_bytes(output, f"{root}/codecs/{codec['file']}",
                              checked_bytes(args.downloads / codec["file"], codec["sha256"]))
                    debian = codec.get("debian_patch")
                    if debian:
                        add_bytes(output, f"{root}/codecs/{debian['file']}",
                                  checked_bytes(args.downloads / debian["file"], debian["sha256"]))
                    for patch in codec.get("patches", []):
                        add_bytes(output, f"{root}/{patch['file']}",
                                  checked_bytes(repo_root / patch["file"], patch["sha256"]))

                if codecs:
                    for rel in STANDALONE_BUILD_FILES:
                        path = repo_root / rel
                        mode = 0o755 if rel.endswith(".sh") else 0o644
                        add_bytes(output, f"{root}/{rel}", path.read_bytes(), mode)


if __name__ == "__main__":
    main()
