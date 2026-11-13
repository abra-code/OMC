#!/usr/bin/env python3
"""icon_png.py - writes an applet icon as a PNG file, on macOS and Linux alike.

Usage: icon_png.py <source> <output.png>

The source is
  - an .icns file: its largest PNG image is written (macOS icons store PNG data for the sizes
    from 32 pixels up, so no conversion is needed);
  - a .png file: copied after checking that it is one;
  - an .icon (Icon Composer) package: the .icns of the same name beside it is used, as the Icons
    folder of AppletBuilder ships both (an .icon itself needs Xcode's actool, macOS only).

Prints the size written ("256x256"). Exit status: 0 written, 1 the source holds no PNG image or
cannot be read, 2 bad arguments or an unsupported kind of source. Standard library only.
"""

import os
import struct
import sys

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def png_size(data):
    """The (width, height) of PNG data, from its IHDR chunk, or None."""
    if len(data) < 24 or not data.startswith(PNG_SIGNATURE) or data[12:16] != b"IHDR":
        return None
    return struct.unpack(">II", data[16:24])


def largest_png_in_icns(data):
    """The largest PNG image in .icns data as (bytes, (width, height)), or None."""
    if len(data) < 8 or data[:4] != b"icns":
        return None
    best = None
    position = 8
    while position + 8 <= len(data):
        _kind, length = struct.unpack(">4sI", data[position:position + 8])
        if length < 8 or position + length > len(data):
            break  # a damaged entry: keep what was found before it
        body = data[position + 8:position + length]
        size = png_size(body)
        if size is not None and (best is None or size[0] * size[1] > best[1][0] * best[1][1]):
            best = (body, size)
        position += length
    return best


def read_source(source):
    """PNG bytes and size for a source, or raises ValueError with the reason."""
    extension = os.path.splitext(source)[1].lower()
    if extension == ".icon":
        source = os.path.splitext(source)[0] + ".icns"
        extension = ".icns"
        if not os.path.isfile(source):
            raise ValueError("no .icns beside the .icon: %s" % source)
    with open(source, "rb") as handle:
        data = handle.read()
    if extension == ".icns":
        found = largest_png_in_icns(data)
        if found is None:
            raise ValueError("no PNG image in %s" % source)
        return found
    if extension == ".png":
        size = png_size(data)
        if size is None:
            raise ValueError("not a PNG file: %s" % source)
        return data, size
    raise LookupError("unsupported icon source (.icns, .icon or .png): %s" % source)


def main(arguments):
    if len(arguments) != 2:
        print("usage: icon_png.py <source .icns|.icon|.png> <output.png>", file=sys.stderr)
        return 2
    source, output = arguments
    try:
        data, size = read_source(source)
    except LookupError as error:
        print("icon_png.py: %s" % error, file=sys.stderr)
        return 2
    except (OSError, ValueError) as error:
        print("icon_png.py: %s" % error, file=sys.stderr)
        return 1
    temporary = output + ".tmp"
    try:
        with open(temporary, "wb") as handle:
            handle.write(data)
        os.replace(temporary, output)
    except OSError as error:
        print("icon_png.py: cannot write %s: %s" % (output, error), file=sys.stderr)
        try:
            os.remove(temporary)
        except OSError:
            pass
        return 1
    print("%dx%d" % size)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
