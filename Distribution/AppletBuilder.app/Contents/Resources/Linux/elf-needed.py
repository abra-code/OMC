#!/usr/bin/env python3
"""elf-needed.py - the shared libraries Linux programs and libraries name (ELF DT_NEEDED), and their
library search paths, read from the files themselves: no readelf (binutils), which a user's machine
may not have. AppletBuilder's build on Linux uses it to list what an applet's own bundled programs
need from the system in the applet's CommandEngineLinuxRequires (lib.build.sh,
update_linux_requires). The ELF reading follows OMC's Linux/set-elf-runpath.py.

Usage:
    elf-needed.py needed <file>...     one line per needed library: "<soname><TAB><file>"; a file
                                       that is not a 64-bit little-endian dynamic ELF file (a script,
                                       a text file, a static program) is passed over silently
    elf-needed.py runpath <file>       the file's library search path (RUNPATH, else RPATH), or nothing

Exit status: 0 done, 1 a file could not be read, 64 bad arguments.
"""

import struct
import sys

PT_LOAD = 1
PT_DYNAMIC = 2
DT_NULL = 0
DT_NEEDED = 1
DT_STRTAB = 5
DT_STRSZ = 10
DT_RPATH = 15
DT_RUNPATH = 29


class NotDynamicElf(Exception):
    pass


class Elf:
    def __init__(self, data):
        if len(data) < 64 or data[:4] != b"\x7fELF":
            raise NotDynamicElf("not an ELF file")
        if data[4] != 2 or data[5] != 1:
            raise NotDynamicElf("not a 64-bit little-endian ELF file")
        self.data = data
        (self.phoff,) = struct.unpack_from("<Q", data, 0x20)
        (self.phentsize, self.phnum) = struct.unpack_from("<HH", data, 0x36)
        if self.phentsize != 56:
            raise NotDynamicElf("unexpected program header size")
        self.segments = []
        for index in range(self.phnum):
            fields = struct.unpack_from("<IIQQQQQQ", data, self.phoff + index * self.phentsize)
            self.segments.append(fields)  # type, flags, offset, vaddr, paddr, filesz, memsz, align
        self.dynamic = self.read_dynamic()
        strtab = self.single(DT_STRTAB)
        if strtab is None:
            # Damaged when it names anything (the names are in the string table)
            if any(tag in (DT_NEEDED, DT_RPATH, DT_RUNPATH) for (tag, _) in self.dynamic):
                raise ValueError("no dynamic string table")
            raise NotDynamicElf("no dynamic string table")
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
        raise NotDynamicElf("no dynamic section (a static program)")

    def single(self, tag):
        for (entry_tag, value) in self.dynamic:
            if entry_tag == tag:
                return value
        return None

    def file_offset(self, address):
        for (kind, _, offset, vaddr, _, filesz, _, _) in self.segments:
            if kind == PT_LOAD and vaddr <= address < vaddr + filesz:
                return offset + (address - vaddr)
        # A damaged file, named by the caller: not one to pass over silently
        raise ValueError("the dynamic string table is in no loaded segment")

    def string(self, offset):
        if offset >= self.strsz:
            raise ValueError("a name outside the dynamic string table")
        start = self.strtab + offset
        end = self.data.index(b"\0", start, self.strtab + self.strsz)
        return self.data[start:end].decode("utf-8", "replace")

    def needed(self):
        return [self.string(value) for (tag, value) in self.dynamic if tag == DT_NEEDED]

    def runpath(self):
        for wanted in (DT_RUNPATH, DT_RPATH):
            for (tag, value) in self.dynamic:
                if tag == wanted:
                    return self.string(value)
        return ""


def read_elf(path):
    with open(path, "rb") as source:
        # The ELF magic first: a large data file is not read whole
        if source.read(4) != b"\x7fELF":
            raise NotDynamicElf("not an ELF file")
        source.seek(0)
        return Elf(source.read())


def main(arguments):
    if len(arguments) >= 2 and arguments[0] == "needed":
        failed = False
        for path in arguments[1:]:
            try:
                elf = read_elf(path)
                names = elf.needed()
            except NotDynamicElf:
                continue
            except (OSError, struct.error, ValueError, IndexError) as problem:
                # A damaged file is named, and the others are still read
                print("elf-needed: %s: %s" % (path, problem), file=sys.stderr)
                failed = True
                continue
            for soname in names:
                print("%s\t%s" % (soname, path))
        return 1 if failed else 0
    if len(arguments) == 2 and arguments[0] == "runpath":
        try:
            elf = read_elf(arguments[1])
        except NotDynamicElf:
            return 0
        path = elf.runpath()
        if path:
            print(path)
        return 0
    print(__doc__.split("Usage:")[1].split("Exit status")[0].rstrip(), file=sys.stderr)
    return 64


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, struct.error, ValueError, IndexError) as problem:
        print("elf-needed: %s" % problem, file=sys.stderr)
        sys.exit(1)
