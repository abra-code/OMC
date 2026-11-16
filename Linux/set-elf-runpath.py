#!/usr/bin/env python3
"""Shows or replaces the library search path (DT_RUNPATH, or an old DT_RPATH) of a 64-bit
little-endian ELF file (Linux on aarch64 or x86_64), in place.

Linux/make-applet-bundle.sh uses it on the engine programs it puts in a bundle: the build leaves the
toolchain's Swift folder and the build machine's own folders there; a bundle gets the folder of the
engine programs' Swift runtime version instead (/usr/lib/command-engine/swift-<runtime version>, the
command-engine-swift-<runtime version> package; see Linux/Packaging/swift-runtime-versions).

The new path is written over the old one in the dynamic string table, padded with zero bytes, as
chrpath does: nothing else in the file moves, so it must not be longer than the old path. The file is
refused, unchanged, when another name in the table shares the old path's bytes (a linker may store a
string as the tail of a longer one).

Usage:
    set-elf-runpath.py print <file>              the current path, or nothing when there is none
    set-elf-runpath.py set <file> <path>         replace it (a file with no path is refused)

Exit status: 0 done, 1 refused or failed (the file unchanged), 64 bad arguments.
"""

import struct
import sys

PT_LOAD = 1
PT_DYNAMIC = 2
DT_NULL = 0
DT_NEEDED = 1
DT_STRTAB = 5
DT_STRSZ = 10
DT_SONAME = 14
DT_RPATH = 15
DT_RUNPATH = 29
DT_CONFIG = 0x6FFFFEFA
DT_DEPAUDIT = 0x6FFFFEFB
DT_AUDIT = 0x6FFFFEFC
DT_AUXILIARY = 0x7FFFFFFD
DT_FILTER = 0x7FFFFFFF
SHT_DYNSYM = 11
SHT_GNU_VERDEF = 0x6FFFFFFD
SHT_GNU_VERNEED = 0x6FFFFFFE


class Refused(Exception):
    pass


class Elf:
    def __init__(self, data):
        if len(data) < 64 or data[:4] != b"\x7fELF":
            raise Refused("not an ELF file")
        if data[4] != 2 or data[5] != 1:
            raise Refused("not a 64-bit little-endian ELF file")
        self.data = data
        (self.phoff, self.shoff) = struct.unpack_from("<QQ", data, 0x20)
        (self.phentsize, self.phnum, self.shentsize, self.shnum) = struct.unpack_from("<HHHH", data, 0x36)
        if self.phentsize != 56 or (self.shoff and self.shentsize != 64):
            raise Refused("unexpected program or section header size")
        if self.shoff and self.shnum == 0:
            # Extended numbering: the count is in the first section header's size
            self.shnum = struct.unpack_from("<Q", data, self.shoff + 0x20)[0]
        self.segments = []
        for index in range(self.phnum):
            fields = struct.unpack_from("<IIQQQQQQ", data, self.phoff + index * self.phentsize)
            self.segments.append(fields)  # type, flags, offset, vaddr, paddr, filesz, memsz, align
        self.dynamic = self.read_dynamic()
        strtab = self.single(DT_STRTAB)
        if strtab is None:
            raise Refused("no dynamic string table")
        self.strtab = self.file_offset(strtab)
        self.strsz = self.single(DT_STRSZ) or 0

    def read_dynamic(self):
        for (kind, _, offset, _, _, filesz, _, _) in self.segments:
            if kind == PT_DYNAMIC:
                entries = []
                for position in range(offset, offset + filesz, 16):
                    (tag, value) = struct.unpack_from("<qQ", self.data, position)
                    if tag == DT_NULL:
                        break
                    entries.append((tag, value))
                return entries
        raise Refused("no dynamic section (a static program)")

    def single(self, tag):
        for (entry_tag, value) in self.dynamic:
            if entry_tag == tag:
                return value
        return None

    def file_offset(self, address):
        for (kind, _, offset, vaddr, _, filesz, _, _) in self.segments:
            if kind == PT_LOAD and vaddr <= address < vaddr + filesz:
                return offset + (address - vaddr)
        raise Refused("the dynamic string table is in no loaded segment")

    def string(self, offset):
        if offset >= self.strsz:
            raise Refused("a name outside the dynamic string table")
        start = self.strtab + offset
        end = self.data.index(b"\0", start, self.strtab + self.strsz)
        return self.data[start:end]

    def path_entries(self):
        return [(tag, value) for (tag, value) in self.dynamic if tag in (DT_RUNPATH, DT_RPATH)]

    def string_references(self):
        """Every offset into the dynamic string table that something in the file other than the
        library search path entries refers to. A file without section headers is refused: its
        symbol and version names cannot be found, so sharing could not be ruled out."""
        if not self.shoff or not self.shnum:
            raise Refused("no section headers, so the string table's other names cannot be checked")
        references = [value for (tag, value) in self.dynamic
                      if tag in (DT_NEEDED, DT_SONAME, DT_CONFIG, DT_DEPAUDIT, DT_AUDIT, DT_AUXILIARY, DT_FILTER)]
        for index in range(self.shnum):
            (_, kind, _, _, offset, size, _, _, _, entsize) = struct.unpack_from(
                "<IIQQQQIIQQ", self.data, self.shoff + index * self.shentsize)
            if kind == SHT_DYNSYM and entsize:
                for position in range(offset, offset + size, entsize):
                    references.append(struct.unpack_from("<I", self.data, position)[0])
            elif kind == SHT_GNU_VERNEED:
                position = offset
                while True:
                    (_, count, file_name, aux, following) = struct.unpack_from("<HHIII", self.data, position)
                    references.append(file_name)
                    aux_position = position + aux
                    for _ in range(count):
                        (_, _, _, name, aux_following) = struct.unpack_from("<IHHII", self.data, aux_position)
                        references.append(name)
                        aux_position += aux_following
                    if following == 0:
                        break
                    position += following
            elif kind == SHT_GNU_VERDEF:
                position = offset
                while True:
                    (_, _, _, count, _, aux, following) = struct.unpack_from("<HHHHIII", self.data, position)
                    aux_position = position + aux
                    for _ in range(count):
                        (name, aux_following) = struct.unpack_from("<II", self.data, aux_position)
                        references.append(name)
                        aux_position += aux_following
                    if following == 0:
                        break
                    position += following
        return references


def replace(path, new_path):
    with open(path, "rb") as source:
        data = bytearray(source.read())
    elf = Elf(data)
    entries = elf.path_entries()
    if not entries:
        raise Refused("it has no library search path to replace")
    encoded = new_path.encode("utf-8")
    names = elf.string_references()
    path_values = set(value for (_, value) in entries)
    for value in path_values:
        old = elf.string(value)
        if len(encoded) > len(old):
            raise Refused("the new path (%d bytes) is longer than the old one (%d bytes: %s)"
                          % (len(encoded), len(old), old.decode("utf-8", "replace")))
        end = value + len(old)
        # Another name, or another path entry (a DT_RPATH and a DT_RUNPATH at the same offset are
        # one string, replaced once)
        for reference in names + [other for other in path_values if other != value]:
            # At or inside the old path, or a longer string whose tail is the old path
            if value <= reference <= end or (reference < value and reference + len(elf.string(reference)) == end):
                raise Refused("another name in the string table shares the path's bytes")
    for value in path_values:
        old_length = len(elf.string(value))
        start = elf.strtab + value
        data[start:start + old_length] = encoded + b"\0" * (old_length - len(encoded))
    with open(path, "r+b") as target:
        target.write(data)


def main(arguments):
    if len(arguments) == 2 and arguments[0] == "print":
        with open(arguments[1], "rb") as source:
            elf = Elf(source.read())
        for (_, value) in elf.path_entries():
            print(elf.string(value).decode("utf-8", "replace"))
        return 0
    if len(arguments) == 3 and arguments[0] == "set":
        replace(arguments[1], arguments[2])
        return 0
    print(__doc__.split("Usage:")[1].split("Exit status")[0].rstrip(), file=sys.stderr)
    return 64


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Refused as problem:
        print("set-elf-runpath: %s: %s" % (sys.argv[2] if len(sys.argv) > 2 else "", problem), file=sys.stderr)
        sys.exit(1)
    except (OSError, struct.error, ValueError, IndexError) as problem:
        print("set-elf-runpath: %s" % problem, file=sys.stderr)
        sys.exit(1)
