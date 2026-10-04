#!/usr/bin/env python3
"""
macho_set_uuid.py - give an applet's executable a UUID of its own.

Usage: macho_set_uuid.py <executable> <bundle-identifier>
       macho_set_uuid.py --show <executable>

Every applet's executable is a copy of AppletBuilder's, so every applet carried the
same Mach-O UUID (the LC_UUID load command the linker writes). macOS identifies a
program by that UUID for Local Network privacy: with one UUID for all applets, the
permission prompt and the row in System Settings name whichever applet the Mac saw
first, and one answer applies to all of them.

The new UUID is derived from the bundle identifier and the slice's CPU type, so it is
the same after every build and every engine update: macOS keeps the user's answer.
Nothing else in the file changes, and a file that already has its UUID is not written.

The change invalidates the code signature, so this runs just before signing.
Abracode.framework is left alone: it is the same code in every applet.

Exit: 0 on success (prints one line per slice), 1 when the file is not a Mach-O
executable this tool understands or has no LC_UUID, 2 for a usage error.
"""
from __future__ import annotations

import hashlib
import struct
import sys

FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
MH_MAGIC_64 = 0xFEEDFACF
MH_MAGIC = 0xFEEDFACE
LC_UUID = 0x1B

# Mixed into the hash so these UUIDs collide with no other scheme's.
NAMESPACE = b"com.abracode.applet-builder.executable-uuid.1"


class MachOError(Exception):
    pass


def derived_uuid(bundle_id: str, cputype: int) -> bytes:
    """16 bytes from the bundle identifier and CPU type, marked as an RFC 4122 version 5 UUID."""
    digest = hashlib.sha256(NAMESPACE + b"\0" + bundle_id.encode("utf-8") + b"\0" + struct.pack("<I", cputype)).digest()
    raw = bytearray(digest[:16])
    raw[6] = (raw[6] & 0x0F) | 0x50
    raw[8] = (raw[8] & 0x3F) | 0x80
    return bytes(raw)


def format_uuid(raw: bytes) -> str:
    text = raw.hex().upper()
    return f"{text[0:8]}-{text[8:12]}-{text[12:16]}-{text[16:20]}-{text[20:32]}"


def slices(data: bytes) -> list[int]:
    """Offsets of the Mach-O images in the file: one for a thin file, one per architecture."""
    if len(data) < 8:
        raise MachOError("too short to be a Mach-O file")
    magic = struct.unpack(">I", data[:4])[0]
    if magic not in (FAT_MAGIC, FAT_MAGIC_64):
        return [0]
    count = struct.unpack(">I", data[4:8])[0]
    if count == 0 or count > 16:
        raise MachOError(f"a universal file with {count} architectures")
    offsets = []
    position = 8
    for _ in range(count):
        if magic == FAT_MAGIC:
            entry = data[position:position + 20]
            if len(entry) < 20:
                raise MachOError("a cut-off universal header")
            offsets.append(struct.unpack(">IIIII", entry)[2])
            position += 20
        else:
            entry = data[position:position + 32]
            if len(entry) < 32:
                raise MachOError("a cut-off universal header")
            offsets.append(struct.unpack(">IIQQII", entry)[2])
            position += 32
    return offsets


def uuid_field(data: bytes, start: int) -> tuple[int, int]:
    """(CPU type, offset of the 16 UUID bytes) of the Mach-O image at `start`."""
    header = data[start:start + 32]
    if len(header) < 28:
        raise MachOError("a cut-off Mach-O header")
    magic = struct.unpack("<I", header[:4])[0]
    if magic == MH_MAGIC_64:
        header_size = 32
    elif magic == MH_MAGIC:
        header_size = 28
    else:
        raise MachOError("not a little-endian Mach-O image")
    cputype, _, _, command_count, commands_size = struct.unpack("<IIIII", header[4:24])
    position = start + header_size
    end = position + commands_size
    if end > len(data):
        raise MachOError("load commands run past the end of the file")
    for _ in range(command_count):
        if position + 8 > end:
            raise MachOError("a cut-off load command")
        command, size = struct.unpack("<II", data[position:position + 8])
        if size < 8 or position + size > end:
            raise MachOError("a load command with an impossible size")
        if command == LC_UUID:
            if size < 24:
                raise MachOError("an LC_UUID command too small to hold a UUID")
            return cputype, position + 8
        position += size
    raise MachOError("no LC_UUID load command")


def main(argv: list[str]) -> int:
    show = len(argv) == 3 and argv[1] == "--show"
    if not show and (len(argv) != 3 or argv[1].startswith("-") or not argv[2]):
        print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
        return 2
    path = argv[2] if show else argv[1]
    bundle_id = "" if show else argv[2]
    try:
        with open(path, "rb") as handle:
            data = bytearray(handle.read())
        fields = [uuid_field(data, start) for start in slices(data)]
    except (OSError, MachOError, struct.error) as error:
        print(f"macho_set_uuid.py: {path}: {error}", file=sys.stderr)
        return 1
    changed = False
    # Reported only after the write: a caller reading "old -> new" takes it as done.
    lines = []
    for cputype, offset in fields:
        old = bytes(data[offset:offset + 16])
        if show:
            lines.append(f"cputype 0x{cputype:08x}: {format_uuid(old)}")
            continue
        new = derived_uuid(bundle_id, cputype)
        if new == old:
            lines.append(f"cputype 0x{cputype:08x}: {format_uuid(old)} (unchanged)")
            continue
        data[offset:offset + 16] = new
        changed = True
        lines.append(f"cputype 0x{cputype:08x}: {format_uuid(old)} -> {format_uuid(new)}")
    if changed:
        # In place: the file keeps its inode, mode and extended attributes.
        try:
            with open(path, "r+b") as handle:
                handle.write(data)
        except OSError as error:
            print(f"macho_set_uuid.py: {path}: {error}", file=sys.stderr)
            return 1
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
