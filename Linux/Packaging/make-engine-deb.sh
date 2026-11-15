#!/bin/bash
# Linux/Packaging/make-engine-deb.sh - makes the command-engine package (.deb): what every Command
# Engine applet needs from the system, installed once per machine (design:
# Private/linux-applet-install-design.md, "Decisions, 2026-11-15"). For now it holds no program, only
# its dependencies and a short README:
#
# - the system libraries the engine's programs load (the master applet's executable and its support
#   tools), with the versions they need, as dpkg-shlibdeps finds them from the programs;
# - what the engine loads by name rather than links: librsvg2-common (GTK draws SVG icons, the
#   applet's own and its buttons', through it; a KDE Plasma install lacks it), glib-networking (https
#   for libsoup), adwaita-icon-theme (the symbolic icons the engine's windows use, absent outside GNOME
#   unless something pulls it in), python3 (the engine's Support scripts that add an applet to the
#   desktop, linux-app-entry.py and command-services.py, which an applet's install-applet.sh runs; a
#   minimal Debian has no python3);
# - the Swift runtime package of the toolchain the programs were built with,
#   command-engine-swift-<version> (make-swift-runtime-deb.sh).
#
# What one applet needs beyond that (WebKitGTK for a WebView, libshumate for a map, what its bundled
# tools need) is the applet's own list, not this package's.
#
# Usage: make-engine-deb.sh <products folder> <output folder>
#   The products folder is build-linux.sh's, with its command-engine-runtime file and the master
#   applet, CommandApplet.app; the package is written to
#   <output folder>/command-engine_<engine version>-1_<architecture>.deb.
# Needs dpkg-dev (dpkg-shlibdeps) and dpkg-deb (Debian, Ubuntu). Exit status: 0 made, 1 failed,
# 2 bad arguments.

# dpkg-deb refuses a package folder that is not 0755, whatever umask the caller has
umask 022

products="$1"
output="$2"
if [ -z "$products" ] || [ -z "$output" ] || [ $# -ne 2 ]; then
    printf 'Usage: %s <products folder> <output folder>\n' "$0" >&2
    exit 2
fi
# Absolute: dpkg-shlibdeps runs in the work folder
products_given="$products"
products="$(CDPATH= cd -P -- "$products_given" 2>/dev/null && pwd)"
if [ -z "$products" ]; then
    printf 'No products folder at %s\n' "$products_given" >&2
    exit 1
fi
script_folder="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
omc_root="$(CDPATH= cd -P -- "$script_folder/../.." && pwd)"
runtime_file="$products/command-engine-runtime"
swift_version="$(/usr/bin/sed -n 's/^swift_version=//p' "$runtime_file" 2>/dev/null)"
runtime_folder="$(/usr/bin/sed -n 's/^runtime_folder=//p' "$runtime_file" 2>/dev/null)"
if [ -z "$swift_version" ] || [ -z "$runtime_folder" ]; then
    printf 'No swift_version or runtime_folder in %s: build the products with build-linux.sh\n' "$runtime_file" >&2
    exit 1
fi
engine_version="$(/usr/bin/sed -n 's/^OMC_BUNDLE_VERSION *= *\([0-9][0-9.]*\) *$/\1/p' "$omc_root/Common/OmcVersion.xcconfig")"
if [ -z "$engine_version" ]; then
    printf 'Cannot read OMC_BUNDLE_VERSION from %s\n' "$omc_root/Common/OmcVersion.xcconfig" >&2
    exit 1
fi
for tool in /usr/bin/dpkg-shlibdeps /usr/bin/dpkg-deb /usr/bin/dpkg; do
    if [ ! -x "$tool" ]; then
        printf 'No %s (the dpkg-dev package)\n' "$tool" >&2
        exit 1
    fi
done
architecture="$(/usr/bin/dpkg --print-architecture)"
if [ -z "$architecture" ]; then
    printf 'dpkg --print-architecture gave nothing\n' >&2
    exit 1
fi

# The engine's programs as an applet carries them (the master applet: their runtime path is the
# bundle's)
master="$products/CommandApplet.app/Contents"
programs=("$master/Linux/CommandApplet")
for tool in omc_dialog_control omc_next_command plister b64 filt loco; do
    programs+=("$master/Frameworks/Abracode.framework/Support/$tool")
done
for program in "${programs[@]}"; do
    if [ ! -f "$program" ]; then
        printf 'No %s: build all products with build-linux.sh\n' "$program" >&2
        exit 1
    fi
done

/bin/mkdir -p -- "$output"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot make %s\n' "$output" >&2
    exit 1
fi
# Absolute too: the dpkg-shlibdeps log is written from inside the work folder
output_given="$output"
output="$(CDPATH= cd -P -- "$output_given" && pwd)"
if [ -z "$output" ]; then
    printf 'Cannot enter %s\n' "$output_given" >&2
    exit 1
fi
work="$(/usr/bin/mktemp -d "$output/engine-deb.XXXXXX")"
status=$?
if [ "$status" -ne 0 ] || [ -z "$work" ]; then
    printf 'Cannot make a work folder in %s\n' "$output" >&2
    exit 1
fi

# dpkg-shlibdeps works in a source package's folder (it reads debian/control). The Swift runtime's
# libraries are in no installed package here (the toolchain's folder, given with -l since a release
# program does not name it): --ignore-missing-info leaves them out, and the runtime package covers them.
/bin/mkdir -p "$work/debian"
printf 'Source: command-engine\n\nPackage: command-engine\nArchitecture: any\n' > "$work/debian/control"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot write %s\n' "$work/debian/control" >&2
    exit 1
fi
shlibs="$(CDPATH= cd -P -- "$work" && /usr/bin/dpkg-shlibdeps -O --ignore-missing-info "-l$runtime_folder" "${programs[@]}" 2>"$work/shlibdeps.log")"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'dpkg-shlibdeps failed (status %s):\n' "$status" >&2
    /bin/cat "$work/shlibdeps.log" >&2
    exit 1
fi
# --ignore-missing-info also lets a library it cannot find pass as a warning, which would drop that
# library's package from Depends: refuse instead
missing_libraries="$(/usr/bin/grep 'cannot find library' "$work/shlibdeps.log")"
if [ -n "$missing_libraries" ]; then
    printf 'dpkg-shlibdeps could not find libraries the engine needs:\n%s\n' "$missing_libraries" >&2
    exit 1
fi
library_depends="$(printf '%s\n' "$shlibs" | /usr/bin/sed -n 's/^shlibs:Depends=//p')"
if [ -z "$library_depends" ]; then
    printf 'dpkg-shlibdeps named no libraries:\n%s\n' "$shlibs" >&2
    exit 1
fi

package="command-engine"
root="$work/$package"
/bin/mkdir -p "$root/DEBIAN" "$root/usr/share/doc/$package"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot make the package folders in %s\n' "$work" >&2
    exit 1
fi
{
    printf 'Command Engine %s\n\n' "$engine_version"
    printf 'This package brings what every Command Engine applet needs from the system: the GTK and\n'
    printf 'libadwaita libraries, SVG icon support (librsvg2-common), https (glib-networking), the\n'
    printf 'symbolic icons (adwaita-icon-theme), python3 (adding an applet to the desktop), and the\n'
    printf 'Swift %s runtime (command-engine-swift-%s).\n' "$swift_version" "$swift_version"
    printf 'An applet that needs more (WebKitGTK for web pages, for one) says so itself.\n'
} > "$root/usr/share/doc/$package/README"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot write the README\n' >&2
    exit 1
fi
installed_size="$(/usr/bin/du -sk "$root/usr" | /usr/bin/cut -f1)"
# The maintainer is a placeholder until the owner names the address packages are published with
{
    printf 'Package: %s\n' "$package"
    printf 'Version: %s-1\n' "$engine_version"
    printf 'Architecture: %s\n' "$architecture"
    printf 'Maintainer: Command Engine maintainers <maintainer@invalid>\n'
    printf 'Installed-Size: %s\n' "$installed_size"
    printf 'Depends: %s, librsvg2-common, glib-networking, adwaita-icon-theme, python3, command-engine-swift-%s\n' "$library_depends" "$swift_version"
    printf 'Suggests: command-engine-files-nautilus | command-engine-files-thunar | command-engine-files-dolphin\n'
    printf 'Section: misc\n'
    printf 'Priority: optional\n'
    printf 'Description: Command Engine: what Command Engine applets need from the system\n'
    printf ' Installs the libraries every Command Engine applet uses (GTK 4, libadwaita, SVG icon\n'
    printf ' support, https) and the Swift %s runtime they are built with. Applets themselves are\n' "$swift_version"
    printf ' bundles that run from any folder.\n'
} > "$root/DEBIAN/control"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot write %s\n' "$root/DEBIAN/control" >&2
    exit 1
fi
deb="$output/${package}_${engine_version}-1_${architecture}.deb"
/usr/bin/dpkg-deb --root-owner-group --build "$root" "$deb"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'dpkg-deb failed (status %s); the package tree is in %s\n' "$status" "$root" >&2
    exit 1
fi
/bin/rm -rf -- "$work"
printf 'Depends: %s\n' "$library_depends"
printf 'The package: %s\n' "$deb"
exit 0
