#!/usr/bin/env python3
"""Generate a small, distinctive photo library for UI tests.

Creates real image files (not 1x1 placeholders):
  - screenshots
  - exact duplicates
  - blurry photos
  - a sharp night photo
  - a short video
  - a handful of normal photos
"""

from __future__ import annotations

import os
import struct
import sys
import zlib


MINIMAL_MP4 = bytes.fromhex(
    "00000018667479706d703432000000006d70343269736f6d0000000866726565"
    "000000206d646174000000000000000000000000000000000000000000000000"
)


def clamp(value: int) -> int:
    return 0 if value < 0 else 255 if value > 255 else value


def write_png(path: str, width: int, height: int, pixel_fn) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            r, g, b = pixel_fn(x, y)
            raw.extend((r & 255, g & 255, b & 255))
    payload = b"".join(
        [
            b"\x89PNG\r\n\x1a\n",
            chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)),
            chunk(b"IDAT", zlib.compress(bytes(raw), 6)),
            chunk(b"IEND", b""),
        ]
    )
    with open(path, "wb") as handle:
        handle.write(payload)


def screenshot_pixel(x: int, y: int, width: int, height: int, index: int) -> tuple[int, int, int]:
    if y < 28:
        return (20, 20, 24)
    if y > height - 40:
        return (30, 30, 36)
    band = (y // 48 + index) % 4
    palette = ((70, 130, 220), (90, 90, 100), (245, 245, 248), (50, 160, 110))
    return palette[band]


def blurry_pixel(x: int, y: int, width: int, height: int) -> tuple[int, int, int]:
    t = (x / max(width - 1, 1) + y / max(height - 1, 1)) / 2
    value = int(40 + 140 * t)
    return (value, value + 8, value + 16)


def night_pixel(x: int, y: int, width: int, height: int) -> tuple[int, int, int]:
    seed = (x * 374761393 + y * 668265263) & 0xFFFFFFFF
    if seed % 211 == 0:
        return (255, 255, 250)
    if seed % 173 == 0:
        return (240, 230, 180)
    return (4, 6, 14)


def normal_pixel(x: int, y: int, width: int, height: int, index: int) -> tuple[int, int, int]:
    cx, cy = width // 2, height // 2
    dx, dy = x - cx, y - cy
    ring = (dx * dx + dy * dy) // 80
    r = 40 + (index * 37 + ring) % 180
    g = 80 + (index * 19 + x) % 140
    b = 60 + (index * 53 + y) % 160
    return (clamp(r), clamp(g), clamp(b))


def duplicate_pixel(x: int, y: int) -> tuple[int, int, int]:
    return (210, 80 + (x // 8) % 40, 70)


def generate(output_dir: str) -> int:
    os.makedirs(output_dir, exist_ok=True)
    created: list[str] = []

    for i in range(1, 6):
        path = os.path.join(output_dir, f"screenshot_{i:02d}.png")
        write_png(path, 390, 844, lambda x, y, i=i: screenshot_pixel(x, y, 390, 844, i))
        created.append(path)

    for i in range(1, 4):
        a = os.path.join(output_dir, f"duplicate_{i:02d}_a.png")
        b = os.path.join(output_dir, f"duplicate_{i:02d}_b.png")
        write_png(a, 640, 480, duplicate_pixel)
        write_png(b, 640, 480, duplicate_pixel)
        created.extend([a, b])

    for i in range(1, 4):
        path = os.path.join(output_dir, f"blurry_{i:02d}.png")
        write_png(path, 800, 600, lambda x, y: blurry_pixel(x, y, 800, 600))
        created.append(path)

    night = os.path.join(output_dir, "night_sharp.png")
    write_png(night, 800, 600, lambda x, y: night_pixel(x, y, 800, 600))
    created.append(night)

    for i in range(1, 9):
        path = os.path.join(output_dir, f"normal_{i:02d}.png")
        write_png(path, 720, 540, lambda x, y, i=i: normal_pixel(x, y, 720, 540, i))
        created.append(path)

    video = os.path.join(output_dir, "clip_short.mp4")
    with open(video, "wb") as handle:
        handle.write(MINIMAL_MP4)
    created.append(video)

    existing = [path for path in created if os.path.isfile(path) and os.path.getsize(path) > 0]
    print(f"Created {len(existing)} fixture files in {output_dir}")
    for path in existing:
        print(f"  {os.path.basename(path)} {os.path.getsize(path)} bytes")
    if len(existing) < 10:
        raise SystemExit(f"expected at least 10 fixture files, got {len(existing)}")
    return len(existing)


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "/tmp/moments-fixtures"
    generate(target)
