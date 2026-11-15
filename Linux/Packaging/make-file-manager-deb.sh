#!/bin/bash
# Linux/Packaging/make-file-manager-deb.sh - makes the package (.deb) of one file manager plug-in for
# Command Engine applet services (Linux/FileManagerServices: the Services submenu and Launch <Name>
# for an applet bundle): command-engine-files-nautilus (GNOME Files), command-engine-files-thunar
# (Xfce) or command-engine-files-dolphin (KDE Plasma). Each is its own package, so a machine gets only
# its file manager's plug-in and the libraries that one links (a GNOME machine does not pull KIO in);
# the command-engine package suggests them (design: Private/linux-applet-install-design.md).
#
# The plug-in goes where the file manager loads plug-ins from on Debian and Ubuntu, under
# /usr/lib/<multiarch>/ (the folder each plug-in's install.sh finds on such a system):
#   nautilus  nautilus/extensions-4/libcommand-services-nautilus.so
#   thunar    thunarx-3/libcommand-services-thunar.so
#   dolphin   qt6/plugins/kf6/kfileitemaction/command-services-dolphin.so
# Its library Depends come from dpkg-shlibdeps on the plug-in, so the package is made on a machine
# with that file manager installed (where the plug-in is built: Linux/FileManagerServices/build.sh).
# A running file manager loads a new plug-in when it starts again (nautilus -q, thunar -q); Dolphin
# reads it at its next menu.
#
# Usage: make-file-manager-deb.sh <nautilus|thunar|dolphin> <built plug-in> <output folder>
#   The package is written to <output folder>/command-engine-files-<name>_<engine version>-1_<arch>.deb.
# Needs dpkg-dev (dpkg-shlibdeps, dpkg-architecture) and dpkg-deb. Exit status: 0 made, 1 failed,
# 2 bad arguments.

# dpkg-deb refuses a package folder that is not 0755, whatever umask the caller has
umask 022

file_manager="$1"
plugin_given="$2"
output="$3"
if [ -z "$file_manager" ] || [ -z "$plugin_given" ] || [ -z "$output" ] || [ $# -ne 3 ]; then
    printf 'Usage: %s <nautilus|thunar|dolphin> <built plug-in> <output folder>\n' "$0" >&2
    exit 2
fi
case "$file_manager" in
    nautilus)
        plugin_name="libcommand-services-nautilus.so"
        subfolder="nautilus/extensions-4"
        enhances="nautilus"
        title="GNOME Files"
        ;;
    thunar)
        plugin_name="libcommand-services-thunar.so"
        subfolder="thunarx-3"
        enhances="thunar"
        title="Thunar (Xfce)"
        ;;
    dolphin)
        plugin_name="command-services-dolphin.so"
        subfolder="qt6/plugins/kf6/kfileitemaction"
        enhances="dolphin"
        title="Dolphin (KDE Plasma)"
        ;;
    *)
        printf 'Unknown file manager %s: nautilus, thunar or dolphin\n' "$file_manager" >&2
        exit 2
        ;;
esac
if [ ! -f "$plugin_given" ]; then
    printf 'No plug-in at %s\n' "$plugin_given" >&2
    exit 1
fi
# The file its build.sh makes, so another file manager's plug-in cannot go in under this name
given_name="$(/usr/bin/basename -- "$plugin_given")"
if [ "$given_name" != "$plugin_name" ]; then
    printf 'The %s plug-in is %s, not %s\n' "$file_manager" "$plugin_name" "$plugin_given" >&2
    exit 2
fi
# Absolute: dpkg-shlibdeps runs in the work folder
plugin_folder="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$plugin_given")" && pwd)"
if [ -z "$plugin_folder" ]; then
    printf 'Cannot resolve the folder of %s\n' "$plugin_given" >&2
    exit 1
fi
plugin="$plugin_folder/$(/usr/bin/basename -- "$plugin_given")"
script_folder="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
omc_root="$(CDPATH= cd -P -- "$script_folder/../.." && pwd)"
engine_version="$(/usr/bin/sed -n 's/^OMC_BUNDLE_VERSION *= *\([0-9][0-9.]*\) *$/\1/p' "$omc_root/Common/OmcVersion.xcconfig")"
if [ -z "$engine_version" ]; then
    printf 'Cannot read OMC_BUNDLE_VERSION from %s\n' "$omc_root/Common/OmcVersion.xcconfig" >&2
    exit 1
fi
for tool in /usr/bin/dpkg-shlibdeps /usr/bin/dpkg-architecture /usr/bin/dpkg-deb /usr/bin/dpkg; do
    if [ ! -x "$tool" ]; then
        printf 'No %s (the dpkg-dev package)\n' "$tool" >&2
        exit 1
    fi
done
# Both from dpkg-architecture, so they agree (it follows DEB_HOST_ARCH when that is set)
architecture="$(/usr/bin/dpkg-architecture -qDEB_HOST_ARCH 2>/dev/null)"
multiarch="$(/usr/bin/dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null)"
if [ -z "$architecture" ] || [ -z "$multiarch" ]; then
    printf 'Cannot read the architecture (dpkg --print-architecture, dpkg-architecture)\n' >&2
    exit 1
fi

/bin/mkdir -p -- "$output"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot make %s\n' "$output" >&2
    exit 1
fi
# Absolute: the dpkg-shlibdeps log is written from inside the work folder
output_given="$output"
output="$(CDPATH= cd -P -- "$output_given" && pwd)"
if [ -z "$output" ]; then
    printf 'Cannot enter %s\n' "$output_given" >&2
    exit 1
fi
work="$(/usr/bin/mktemp -d "$output/files-deb.XXXXXX")"
status=$?
if [ "$status" -ne 0 ] || [ -z "$work" ]; then
    printf 'Cannot make a work folder in %s\n' "$output" >&2
    exit 1
fi
package="command-engine-files-$file_manager"

# dpkg-shlibdeps works in a source package's folder (it reads debian/control)
/bin/mkdir -p "$work/debian"
printf 'Source: %s\n\nPackage: %s\nArchitecture: any\n' "$package" "$package" > "$work/debian/control"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot write %s\n' "$work/debian/control" >&2
    exit 1
fi
shlibs="$(CDPATH= cd -P -- "$work" && /usr/bin/dpkg-shlibdeps -O "$plugin" 2>"$work/shlibdeps.log")"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'dpkg-shlibdeps failed (status %s):\n' "$status" >&2
    /bin/cat "$work/shlibdeps.log" >&2
    exit 1
fi
library_depends="$(printf '%s\n' "$shlibs" | /usr/bin/sed -n 's/^shlibs:Depends=//p')"
if [ -z "$library_depends" ]; then
    printf 'dpkg-shlibdeps named no libraries:\n%s\n' "$shlibs" >&2
    exit 1
fi

root="$work/$package"
target_folder="$root/usr/lib/$multiarch/$subfolder"
/bin/mkdir -p "$root/DEBIAN" "$target_folder"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot make the package folders in %s\n' "$work" >&2
    exit 1
fi
/bin/cp -- "$plugin" "$target_folder/$plugin_name"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot copy %s\n' "$plugin" >&2
    exit 1
fi
/bin/chmod 644 "$target_folder/$plugin_name"
installed_size="$(/usr/bin/du -sk "$root/usr" | /usr/bin/cut -f1)"
# The maintainer is a placeholder until the owner names the address packages are published with
{
    printf 'Package: %s\n' "$package"
    printf 'Version: %s-1\n' "$engine_version"
    printf 'Architecture: %s\n' "$architecture"
    printf 'Maintainer: Command Engine maintainers <maintainer@invalid>\n'
    printf 'Installed-Size: %s\n' "$installed_size"
    printf 'Depends: %s\n' "$library_depends"
    printf 'Enhances: %s\n' "$enhances"
    printf 'Section: misc\n'
    printf 'Priority: optional\n'
    printf 'Description: Command Engine applet services in %s\n' "$title"
    printf ' Adds a Services submenu with the Command Engine applets'"'"' file services to the\n'
    printf ' right-click menu of %s, and Launch <Name> for a selected applet bundle.\n' "$title"
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
