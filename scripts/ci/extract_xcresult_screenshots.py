#!/usr/bin/env python3
"""Copy PNG/JPEG attachments out of an xcresult so CI can publish them."""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

PNG = b"\x89PNG\r\n\x1a\n"
JPEG = b"\xff\xd8\xff"


def extract(bundle: Path, dest: Path) -> int:
    dest.mkdir(parents=True, exist_ok=True)
    count = 0
    for root, _dirs, files in os.walk(bundle):
        for name in files:
            path = Path(root) / name
            try:
                with path.open("rb") as handle:
                    head = handle.read(8)
            except OSError:
                continue
            if head.startswith(PNG):
                ext = ".png"
            elif head.startswith(JPEG):
                ext = ".jpg"
            elif name.lower().endswith((".png", ".jpg", ".jpeg")):
                ext = path.suffix.lower()
            else:
                continue
            stem = f"{path.parent.name}-{path.stem}"
            out = dest / f"{stem}{ext}"
            index = 1
            while out.exists():
                out = dest / f"{stem}-{index}{ext}"
                index += 1
            shutil.copy2(path, out)
            count += 1
    print(f"extracted {count} images from {bundle} -> {dest}")
    return count


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: extract_xcresult_screenshots.py <xcresult> <dest>", file=sys.stderr)
        return 2
    extract(Path(sys.argv[1]), Path(sys.argv[2]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
