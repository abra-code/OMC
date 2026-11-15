#!/bin/bash
# Linux/Packaging/make-swift-runtime-deb.sh - makes the command-engine-swift-<line> package (.deb):
# the Swift runtime libraries the Command Engine's programs need, from the toolchain they were built
# with, in /usr/lib/command-engine/swift-<line>/, where every applet bundle of that runtime line looks
# for them (Linux/make-applet-bundle.sh sets that runtime path; design in
# Private/linux-applet-install-design.md, "Swift runtime lines"). The line is build-linux.sh's choice
# from Linux/Packaging/swift-runtime-lines: the minor release (6.4) while its line is rolling, so apt
# upgrades the one package in place across patch releases (its version is the toolchain's, 6.4.2-1),
# or an exact release (6.4.3) once the minor's line is frozen. A rolling package gets a new patch
# release only after check-swift-runtime-abi.sh passed against the one it replaces.
#
# The libraries are what the products need, found from the products themselves: the libraries each
# program names (readelf -d NEEDED) that are in the toolchain's runtime folder, and what those name in
# turn. Programs: CommandApplet, the support tools, and ActionUI's helpers when build-linux.sh put
# them beside the products.
#
# Usage: make-swift-runtime-deb.sh <products folder> <output folder>
#   The products folder is build-linux.sh's (with its command-engine-runtime file); the package is
#   written to <output folder>/command-engine-swift-<line>_<Swift version>-1_<architecture>.deb.
# Needs dpkg-deb, dpkg and readelf (Debian, Ubuntu). Exit status: 0 made, 1 failed, 2 bad arguments.

# The package's folders and files must be readable by everyone (dpkg-deb also refuses a DEBIAN
# folder that is not 0755), whatever umask the caller has
umask 022
products="$1"
output="$2"
if [ -z "$products" ] || [ -z "$output" ] || [ $# -ne 2 ]; then
    printf 'Usage: %s <products folder> <output folder>\n' "$0" >&2
    exit 2
fi
runtime_file="$products/command-engine-runtime"
swift_version="$(/usr/bin/sed -n 's/^swift_version=//p' "$runtime_file" 2>/dev/null)"
runtime_line="$(/usr/bin/sed -n 's/^runtime_line=//p' "$runtime_file" 2>/dev/null)"
swift_release="$(/usr/bin/sed -n 's/^swift_release=//p' "$runtime_file" 2>/dev/null)"
if [ "$swift_release" != "1" ]; then
    printf 'The products were built with a Swift snapshot, not a release (%s): no runtime package from them\n' "$runtime_file" >&2
    exit 1
fi
runtime_folder="$(/usr/bin/sed -n 's/^runtime_folder=//p' "$runtime_file" 2>/dev/null)"
if [ -z "$swift_version" ] || [ -z "$runtime_line" ] || [ -z "$runtime_folder" ]; then
    printf 'No swift_version, runtime_line or runtime_folder in %s: build the products with build-linux.sh\n' "$runtime_file" >&2
    exit 1
fi
if [ ! -d "$runtime_folder" ]; then
    printf 'The toolchain runtime folder %s (from %s) is not here\n' "$runtime_folder" "$runtime_file" >&2
    exit 1
fi
for tool in /usr/bin/dpkg-deb /usr/bin/dpkg /usr/bin/readelf; do
    if [ ! -x "$tool" ]; then
        printf 'No %s (dpkg and binutils)\n' "$tool" >&2
        exit 1
    fi
done
architecture="$(/usr/bin/dpkg --print-architecture)"
if [ -z "$architecture" ]; then
    printf 'dpkg --print-architecture gave nothing\n' >&2
    exit 1
fi

# The engine's programs are required (a products folder from a build of one product would give a
# package without some libraries); ActionUI's helpers are taken when build-linux.sh put them there
programs=()
for program in CommandApplet omc_dialog_control omc_next_command plister b64 filt loco; do
    if [ ! -f "$products/$program" ]; then
        printf 'No %s in %s: build all products with build-linux.sh\n' "$program" "$products" >&2
        exit 1
    fi
    programs+=("$products/$program")
done
for program in ActionUIViewer actionui-verify; do
    if [ -f "$products/$program" ]; then
        programs+=("$products/$program")
    fi
done

# The libraries a file names, one per line
needed_libraries() { # <ELF file>
    local dynamic_section
    dynamic_section="$(/usr/bin/readelf -d -- "$1")"
    local readelf_status=$?
    if [ "$readelf_status" -ne 0 ]; then
        return "$readelf_status"
    fi
    printf '%s\n' "$dynamic_section" | /usr/bin/sed -n 's/.*(NEEDED).*\[\(.*\)\]$/\1/p'
}

# Breadth-first over the runtime folder: a list of names already taken, a queue of files to read
libraries=""
queue=("${programs[@]}")
while [ ${#queue[@]} -gt 0 ]; do
    file="${queue[0]}"
    queue=("${queue[@]:1}")
    names="$(needed_libraries "$file")"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'readelf could not read %s\n' "$file" >&2
        exit 1
    fi
    for library in $names; do
        if [ ! -f "$runtime_folder/$library" ]; then
            continue # a system library
        fi
        case " $libraries " in
            *" $library "*) continue ;;
        esac
        libraries="$libraries $library"
        queue+=("$runtime_folder/$library")
    done
done
if [ -z "$libraries" ]; then
    printf 'The programs name no library from %s: nothing to package\n' "$runtime_folder" >&2
    exit 1
fi

/bin/mkdir -p -- "$output"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot make %s\n' "$output" >&2
    exit 1
fi
work="$(/usr/bin/mktemp -d "$output/swift-runtime-deb.XXXXXX")"
status=$?
if [ "$status" -ne 0 ] || [ -z "$work" ]; then
    printf 'Cannot make a work folder in %s\n' "$output" >&2
    exit 1
fi
package="command-engine-swift-$runtime_line"
root="$work/$package"
library_folder="$root/usr/lib/command-engine/swift-$runtime_line"
/bin/mkdir -p "$root/DEBIAN" "$library_folder"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot make the package folders in %s\n' "$work" >&2
    exit 1
fi
for library in $libraries; do
    # -L: the file, should the toolchain hold a link
    /bin/cp -L -- "$runtime_folder/$library" "$library_folder/$library"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'Cannot copy %s\n' "$runtime_folder/$library" >&2
        exit 1
    fi
    /bin/chmod 644 "$library_folder/$library"
done

# The C and C++ libraries the runtime itself names, at least the build machine's glibc release
glibc_version="$(/usr/bin/dpkg-query -W -f='${Version}' libc6 2>/dev/null | /usr/bin/sed 's/-.*//')"
if [ -z "$glibc_version" ]; then
    printf 'Cannot read the version of libc6 (dpkg-query)\n' >&2
    exit 1
fi
installed_size="$(/usr/bin/du -sk "$root/usr" | /usr/bin/cut -f1)"
library_count="$(printf '%s\n' $libraries | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
# The maintainer is a placeholder until the owner names the address packages are published with
{
    printf 'Package: %s\n' "$package"
    printf 'Version: %s-1\n' "$swift_version"
    printf 'Architecture: %s\n' "$architecture"
    printf 'Maintainer: Command Engine maintainers <maintainer@invalid>\n'
    printf 'Installed-Size: %s\n' "$installed_size"
    printf 'Depends: libc6 (>= %s), libstdc++6, libgcc-s1\n' "$glibc_version"
    printf 'Section: libs\n'
    printf 'Priority: optional\n'
    printf 'Description: Swift %s runtime for Command Engine applets\n' "$runtime_line"
    printf ' The %s Swift runtime libraries (from Swift %s) that Command Engine applets of the\n' "$library_count" "$swift_version"
    printf ' Swift %s runtime line need, in /usr/lib/command-engine/swift-%s, where they look.\n' "$runtime_line" "$runtime_line"
} > "$root/DEBIAN/control"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot write %s\n' "$root/DEBIAN/control" >&2
    exit 1
fi
deb="$output/${package}_${swift_version}-1_${architecture}.deb"
/usr/bin/dpkg-deb --root-owner-group --build "$root" "$deb"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'dpkg-deb failed (status %s); the package tree is in %s\n' "$status" "$root" >&2
    exit 1
fi
/bin/rm -rf -- "$work"
printf '%s libraries:%s\n' "$library_count" "$libraries"
printf 'The package: %s\n' "$deb"
exit 0
