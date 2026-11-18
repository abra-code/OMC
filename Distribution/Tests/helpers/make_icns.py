"""Writes an .icns fixture for 60-icon-png.test.sh.

Usage: make_icns.py <output.icns> <size> [<size> ...]

One entry per size, each holding a stand-in PNG: the signature, an IHDR chunk with that width
and height, and the size again as text after it, so a test can tell which entry was copied.
icon_png.py reads only the signature and the IHDR size, so no image data is needed.
"""

import struct
import sys


def stand_in_png(side):
    ihdr = struct.pack(">II", side, side) + b"\x08\x06\x00\x00\x00"
    chunk = struct.pack(">I", len(ihdr)) + b"IHDR" + ihdr + b"\x00\x00\x00\x00"
    return b"\x89PNG\r\n\x1a\n" + chunk + ("size %d" % side).encode("ascii")


def main(arguments):
    if len(arguments) < 2:
        sys.stderr.write("usage: make_icns.py <output.icns> <size> [<size> ...]\n")
        return 2
    output = arguments[0]
    entries = b""
    for index, side in enumerate(int(text) for text in arguments[1:]):
        body = stand_in_png(side)
        kind = ("ic%02d" % (index + 1)).encode("ascii")
        entries += kind + struct.pack(">I", len(body) + 8) + body
    with open(output, "wb") as handle:
        handle.write(b"icns" + struct.pack(">I", len(entries) + 8) + entries)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
