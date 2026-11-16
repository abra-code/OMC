#!/bin/bash
# Linux/Packaging/check-swift-runtime-abi.sh - the first check before a new Swift patch release goes
# into the folder of its minor release (Linux/Packaging/swift-runtime-versions, "rolling"): compares
# the symbols each runtime library exports in that folder now with the candidate's, library by
# library.
#
# A library of the current runtime missing from the candidate, or a symbol it exports that the
# candidate does not (same name and kind: function, data, ...), is a break: applets built with the
# current release may call it. Symbols the candidate adds are fine. Passing is necessary, not
# sufficient: a changed type layout keeps every symbol, so the previous engine releases' tests must
# also pass against the candidate (check-swift-runtime-tests.sh, with each release's tests archive
# from make-tests-archive.sh) before it replaces the minor release's package; failing either means
# the minor release's folder stays at the current release for good (swift-runtime-versions:
# "<minor> frozen <current release>").
#
# Usage: check-swift-runtime-abi.sh <current runtime folder> <candidate runtime folder>
#   Each folder holds the runtime libraries: an installed one (/usr/lib/command-engine/swift-6.4), a
#   package unpacked with "dpkg-deb -x <package>.deb <folder>" (then
#   <folder>/usr/lib/command-engine/swift-<runtime version>), or a toolchain's /usr/lib/swift/linux
#   (only the current folder's libraries are compared).
# Needs nm (binutils). Exit status: 0 no break found, 1 a break found or a step failed, 2 bad arguments.

current="$1"
candidate="$2"
if [ -z "$current" ] || [ -z "$candidate" ] || [ $# -ne 2 ]; then
    printf 'Usage: %s <current runtime folder> <candidate runtime folder>\n' "$0" >&2
    exit 2
fi
for folder in "$current" "$candidate"; do
    if [ ! -d "$folder" ]; then
        printf 'No folder %s\n' "$folder" >&2
        exit 2
    fi
done
if [ ! -x /usr/bin/nm ]; then
    printf 'No /usr/bin/nm (binutils)\n' >&2
    exit 1
fi
work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/swift-abi.XXXXXX")"
status=$?
if [ "$status" -ne 0 ] || [ -z "$work" ]; then
    printf 'Cannot make a work folder\n' >&2
    exit 1
fi

# The symbols <library> exports, one "<name> <kind>" per line, sorted, into <file>; returns nm's status
exported_symbols() { # <library> <file>
    local listing
    listing="$(/usr/bin/nm -D --defined-only --format=posix -- "$1" 2>/dev/null)"
    local nm_status=$?
    if [ "$nm_status" -ne 0 ]; then
        return "$nm_status"
    fi
    # posix format: "<name> <kind letter> <value> [<size>]"; the value and size change between builds.
    # The letter names a section, so it is reduced to the kind a caller binds to: a function (text,
    # weak, indirect) or data (initialized, zeroed, read-only, small, weak object, unique), so that a
    # variable moving from .data to .bss is not a break. No symbols is an empty file, not one blank line.
    if [ -z "$listing" ]; then
        : > "$2"
        return $?
    fi
    printf '%s\n' "$listing" | /usr/bin/cut -d ' ' -f 1,2 \
        | /usr/bin/sed -e 's/ [TWi]$/ function/' -e 's/ [DBRGSVu]$/ data/' \
        | LC_ALL=C /usr/bin/sort -u > "$2"
    return 0
}

libraries=0
breaks=0
for library_path in "$current"/*.so "$current"/*.so.*; do
    if [ ! -f "$library_path" ]; then
        continue
    fi
    library="$(/usr/bin/basename -- "$library_path")"
    libraries=$((libraries + 1))
    if [ ! -f "$candidate/$library" ]; then
        printf 'BREAK %s: not in the candidate\n' "$library"
        breaks=$((breaks + 1))
        continue
    fi
    exported_symbols "$library_path" "$work/current"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'nm could not read %s\n' "$library_path" >&2
        /bin/rm -rf -- "$work"
        exit 1
    fi
    exported_symbols "$candidate/$library" "$work/candidate"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'nm could not read %s\n' "$candidate/$library" >&2
        /bin/rm -rf -- "$work"
        exit 1
    fi
    removed="$(LC_ALL=C /usr/bin/comm -23 "$work/current" "$work/candidate")"
    added_count="$(LC_ALL=C /usr/bin/comm -13 "$work/current" "$work/candidate" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
    if [ -n "$removed" ]; then
        removed_count="$(printf '%s\n' "$removed" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
        printf 'BREAK %s: %s exported symbols gone or changed in kind, %s added; the first:\n' "$library" "$removed_count" "$added_count"
        printf '%s\n' "$removed" | /usr/bin/head -n 10 | /usr/bin/sed 's/^/  /'
        breaks=$((breaks + 1))
    else
        printf 'ok    %s: every exported symbol kept, %s added\n' "$library" "$added_count"
    fi
done
/bin/rm -rf -- "$work"
if [ "$libraries" -eq 0 ]; then
    printf 'No libraries in %s\n' "$current" >&2
    exit 1
fi
if [ "$breaks" -ne 0 ]; then
    printf '%s of %s libraries break: freeze the minor release at the current release (swift-runtime-versions).\n' "$breaks" "$libraries"
    exit 1
fi
printf 'No symbol break in %s libraries. Next: check-swift-runtime-tests.sh, the previous engine releases'"'"' tests against the candidate.\n' "$libraries"
exit 0
