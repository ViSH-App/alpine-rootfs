#!/usr/bin/env python3
"""Generate RootfsPatch.bundle/manifest.plist from patch/VERSION + patch/files.

The manifest is consumed by iSH's FsApplyOverlay(): an integer `version` and a
`files` array of {src, dst}. src is bundle-relative ("files/<rel>"), dst is the
guest absolute path ("/<rel>"). The files tree IS the mapping — there is no
hand-maintained manifest to drift out of sync.

Usage: gen_patch_manifest.py <patch-dir> <output-plist>
"""
import plistlib
import sys
from pathlib import Path


def main() -> None:
    patch_dir = Path(sys.argv[1])
    out = Path(sys.argv[2])

    version = int((patch_dir / "VERSION").read_text().strip())
    if version <= 0:
        sys.exit("patch VERSION must be a positive integer")

    entries = []
    files_dir = patch_dir / "files"
    if files_dir.is_dir():
        for p in sorted(files_dir.rglob("*")):
            if p.is_file() and p.name not in (".gitkeep", ".DS_Store"):
                rel = p.relative_to(files_dir).as_posix()
                entries.append({"src": f"files/{rel}", "dst": f"/{rel}"})

    with open(out, "wb") as f:
        plistlib.dump({"version": version, "files": entries}, f, sort_keys=False)


if __name__ == "__main__":
    main()
