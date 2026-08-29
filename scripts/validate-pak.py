#!/usr/bin/env python3
"""Validate this pak against the content-pak contract.

Deliberately does not reimplement the rules. It loads the contract's own
reference validator (`content_model.py`) and schema out of a checkout of the
public leaf-contracts repository, so there is exactly one definition of what a
valid `provides` block is and this repository cannot drift from it quietly.

That checkout is fetched by `make validate` from the public leaf-contracts
repository at a pinned ref, or you can point --contract at a local clone.
Either way nothing outside this repository is assumed to exist.

    python3 scripts/validate-pak.py --contract <leaf-contracts> --pak pak/
    python3 scripts/validate-pak.py --contract <leaf-contracts> --pak build/package/ScummVM.pak --packaged
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def load_contract(contract_root: Path):
    scripts = contract_root / "contracts" / "leaf-content" / "scripts"
    schema = contract_root / "contracts" / "leaf-content" / "content-paks-v1.schema.json"
    scrape_schema = (
        contract_root / "contracts" / "leaf-content" /
        "content-scrape-v1.schema.json"
    )
    if not scripts.is_dir() or not schema.is_file() or not scrape_schema.is_file():
        raise SystemExit(
            f"not a leaf-contracts checkout: {contract_root}\n"
            "expected CONTENT-1 and CONTENT-SCRAPE-1 under contracts/leaf-content/"
        )
    sys.path.insert(0, str(scripts))
    # minischema lives with the SVC-1 contract and is shared, not copied.
    sys.path.insert(0, str(contract_root / "contracts" / "leaf-services" / "scripts"))
    import content_model  # noqa: E402
    import minischema  # noqa: E402
    import scrape_model  # noqa: E402

    return (
        content_model,
        scrape_model,
        minischema,
        json.loads(schema.read_text()),
        json.loads(scrape_schema.read_text()),
    )


def authored_paths_present(manifest: dict, pak_dir: Path) -> bool:
    """Only the generated libretro binary and .info may be absent pre-build."""
    provides = manifest.get("provides", {})
    authored: list[str] = []
    for system in provides.get("systems", []):
        for key in ("icon_flat", "icon_photographic"):
            value = system.get(key)
            if isinstance(value, str) and value:
                authored.append(value)
    for core in provides.get("cores", []):
        if core.get("type") == "standalone":
            value = core.get("path")
            if isinstance(value, str) and value:
                authored.append(value)
    return all((pak_dir / value).is_file() for value in authored)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", required=True, type=Path)
    parser.add_argument("--pak", required=True, type=Path)
    parser.add_argument(
        "--packaged",
        action="store_true",
        help="the pak directory is a built package, so every declared file must "
             "actually be present; the source tree legitimately lacks the core "
             "until `make core` has run",
    )
    args = parser.parse_args()

    content_model, scrape_model, minischema, schema, scrape_schema = load_contract(
        args.contract.resolve()
    )

    pak_dir = args.pak.resolve()
    manifest_path = pak_dir / "pak.json"
    if not manifest_path.is_file():
        raise SystemExit(f"no pak.json in {pak_dir}")
    manifest = json.loads(manifest_path.read_text())

    ok, err = minischema.is_valid(manifest, schema)
    if not ok:
        print(f"FAIL schema: {err}")
        return 1
    print("ok   schema: content-paks-v1")

    scrape_ok, scrape_err = minischema.is_valid(manifest, scrape_schema)
    if not scrape_ok:
        print(f"FAIL content scrape schema: {scrape_err}")
        return 1
    scrape_violations = scrape_model.validate(manifest)
    if scrape_violations:
        for reason in sorted(scrape_violations):
            print(f"FAIL {reason}")
        return 1
    print("ok   schema: content-scrape-v1")

    violations = content_model.validate_manifest(
        manifest, str(pak_dir),
        {"install_lane": "platform", "source_id": "primary"},
    )

    if not args.packaged:
        # Before `make core` the .so and .info do not exist yet. Missing files
        # are the ONLY violation tolerated here, and only in the source tree --
        # `make check` re-runs this against the built package with --packaged,
        # where nothing is excused.
        excused = {"missing-file"} if authored_paths_present(manifest, pak_dir) else set()
        remaining = violations - excused
        if violations & excused:
            print("note unbuilt: declared files are absent in the source tree "
                  "(run `make core`); re-checked strictly against the package")
    else:
        remaining = violations

    if remaining:
        for reason in sorted(remaining):
            print(f"FAIL {reason}")
        return 1

    if args.packaged:
        for rel in ("cores/scummvm/extra", "cores/scummvm/theme"):
            directory = pak_dir / rel
            if not directory.is_dir() or not any(path.is_file() for path in directory.iterdir()):
                print(f"FAIL missing bundled data: {rel}")
                return 1
        print("ok   bundled data: upstream extra + theme")

    warnings = content_model.manifest_warnings(manifest)
    for warning in sorted(warnings):
        print(f"warn {warning}")

    provides = manifest["provides"]
    systems = [s["id"] for s in provides.get("systems", [])]
    cores = [c["id"] for c in provides.get("cores", [])]
    print(f"ok   provides: systems={systems or '-'} cores={cores or '-'}")

    # A pure content pak, which is the case this repository exists to
    # demonstrate. A launch.sh here would make it a hybrid and change how the
    # storefront and the launcher treat it.
    if (pak_dir / "launch.sh").exists():
        print("FAIL launch.sh present: this is meant to be a PURE content pak")
        return 1
    print("ok   no launch.sh: pure content pak, not listed in Apps")

    print("PASS validate-pak")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
