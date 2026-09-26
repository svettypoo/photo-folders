#!/usr/bin/env python3
"""Draws the 1024x1024 app icon (a folder holding a photo) with no dependencies."""
import struct
import sys
import zlib

S = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rounded_rect(x, y, x0, y0, x1, y1, r):
    if x < x0 or x > x1 or y < y0 or y > y1:
        return False
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def pixel(x, y):
    # background: deep blue to violet diagonal
    t = (x + y) / (2 * S)
    col = lerp((32, 76, 214), (124, 58, 237), t)
    # folder back with tab
    back = rounded_rect(x, y, 150, 300, 874, 820, 60) or rounded_rect(x, y, 150, 240, 470, 360, 40)
    if back:
        col = (255, 196, 61)
    # photo sticking out
    if rounded_rect(x, y, 230, 250, 800, 640, 30):
        col = (250, 250, 250)
        if rounded_rect(x, y, 260, 280, 770, 610, 18):
            sky = lerp((125, 196, 255), (190, 228, 255), (y - 280) / 330)
            col = sky
            # sun
            if (x - 670) ** 2 + (y - 360) ** 2 <= 45 ** 2:
                col = (255, 214, 64)
            # mountains
            if y > 610 - (260 - abs(x - 430)) * 1.0 and y > 380:
                col = (58, 160, 110)
            if y > 610 - (170 - abs(x - 640)) * 1.1 and y > 440:
                col = (40, 128, 90)
    # folder front
    if rounded_rect(x, y, 150, 470, 874, 830, 60):
        col = lerp((255, 206, 84), (255, 170, 40), (y - 470) / 360)
    return col


def main(path):
    raw = bytearray()
    for y in range(S):
        raw.append(0)
        for x in range(S):
            raw.extend(pixel(x, y))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", S, S, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    main(sys.argv[1])
