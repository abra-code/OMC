#!/bin/bash
# make-applet-archive.sh - makes the download archive of a Linux Command Engine applet: the applet
# bundle and, beside it, install.sh, the installer that brings everything the applet needs on a machine
# that may not have the system packages Command Engine applets need yet. Runs on Linux, on an applet
# bundle made for Linux (by AppletBuilder or make-applet-bundle.sh), on a machine where the applet runs
# (the plister in its framework reads the plists).
#
# The archive, <Name>-<applet version>-linux-<architecture>.tar.gz, holds one folder of the same name:
#   <Name>.app       the applet
#   install.sh       the installer (this folder's install.sh); the user runs ./install.sh
#   install-info     what install.sh needs to know: the applet's name and identifier, its engine
#                    version, the Swift release its programs were built with and the Swift runtime
#                    version they load (6.4: the command-engine-swift-6.4 package, which takes the
#                    compatible 6.4.x releases), the architecture, and the address the packages are
#                    downloaded from
#   packages.sha256  with --packages: the SHA-256 of each package install.sh may use;
#                    install.sh refuses a package that does not match
#   packages/        with --include-packages: those packages themselves, so nothing is downloaded
#   README.txt       how to install
#
# Usage: make-applet-archive.sh [--packages <folder>] [--include-packages] [--release-url <url>]
#                               <applet>.app <output folder>
#   --packages          a folder holding the packages of the applet's engine release (command-engine
#                       and command-engine-swift-<runtime version>, .deb and/or .rpm, as OMC's
#                       release publishes them); their checksums go into the archive
#   --include-packages  also copies those packages into the archive (needs --packages)
#   --release-url       where install.sh downloads the packages from (default: OMC's GitHub release
#                       of the engine version, https://github.com/abra-code/OMC/releases/download/v<version>)
# Exit status: 0 made, 1 failed, 2 bad arguments.

umask 022

packages_folder=""
include_packages=0
release_url=""
arguments=()
while [ $# -gt 0 ]; do
    case "$1" in
        --packages|--release-url)
            if [ $# -lt 2 ] || [ -z "$2" ]; then
                printf 'make-applet-archive.sh: %s needs a value\n' "$1" >&2
                exit 2
            fi
            if [ "$1" = "--packages" ]; then
                packages_folder="$2"
            else
                release_url="$2"
            fi
            shift 2
            ;;
        --include-packages) include_packages=1; shift ;;
        -*)
            printf 'make-applet-archive.sh: unknown option %s\n' "$1" >&2
            exit 2
            ;;
        *) arguments+=("$1"); shift ;;
    esac
done
if [ ${#arguments[@]} -ne 2 ]; then
    printf 'Usage: %s [--packages <folder>] [--include-packages] [--release-url <url>] <applet>.app <output folder>\n' "$0" >&2
    exit 2
fi
if [ "$include_packages" -eq 1 ] && [ -z "$packages_folder" ]; then
    printf 'make-applet-archive.sh: --include-packages needs --packages <folder>\n' >&2
    exit 2
fi

bundle="$(CDPATH= cd -P -- "${arguments[0]}" 2>/dev/null && pwd)"
output="${arguments[1]}"
if [ -z "$bundle" ] || [ ! -f "$bundle/Contents/Info.plist" ]; then
    printf 'No applet bundle at %s\n' "${arguments[0]}" >&2
    exit 1
fi
script_folder="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
installer="$script_folder/install.sh"
if [ ! -f "$installer" ]; then
    printf 'No %s\n' "$installer" >&2
    exit 1
fi
applet_name="$(/usr/bin/basename -- "$bundle" .app)"
info_plist="$bundle/Contents/Info.plist"
framework="$bundle/Contents/Frameworks/Command.framework"
plister="$framework/Support/plister"
runtime_file="$framework/command-engine-runtime"
executable="$bundle/Contents/Linux/$applet_name"
if [ ! -x "$bundle/Contents/Linux/install-applet.sh" ]; then
    printf 'No Contents/Linux/install-applet.sh in %s: build it for Linux with AppletBuilder\n' "$bundle" >&2
    exit 1
fi
if [ ! -f "$runtime_file" ]; then
    printf 'No %s: the applet'"'"'s engine is older than this script; rebuild the applet with a current AppletBuilder, forcing the framework update (appletbuilder build --force: a build of the same engine version keeps the old framework)\n' "$runtime_file" >&2
    exit 1
fi
if [ ! -x "$plister" ]; then
    printf 'No plister in %s\n' "$framework/Support" >&2
    exit 1
fi

# The Linux executable: the bundle's own name, else the only program in Contents/Linux
if [ ! -x "$executable" ] || [ -d "$executable" ]; then
    executable=""
    for candidate in "$bundle/Contents/Linux"/*; do
        if [ -f "$candidate" ] && [ -x "$candidate" ] && [ "${candidate##*/}" != "install-applet.sh" ]; then
            executable="$candidate"
        fi
    done
fi
if [ -z "$executable" ]; then
    printf 'No executable in %s\n' "$bundle/Contents/Linux" >&2
    exit 1
fi

bundle_identifier="$("$plister" get value "$info_plist" /CFBundleIdentifier 2>/dev/null)"
status=$?
if [ "$status" -ne 0 ] || [ -z "$bundle_identifier" ]; then
    printf 'Cannot read CFBundleIdentifier with %s (status %s): are the command-engine and Swift runtime packages installed here?\n' "$plister" "$status" >&2
    exit 1
fi
applet_version="$("$plister" get value "$info_plist" /CFBundleShortVersionString 2>/dev/null)"
if [ -z "$applet_version" ]; then
    applet_version="$("$plister" get value "$info_plist" /CFBundleVersion 2>/dev/null)"
fi
if [ -z "$applet_version" ]; then
    applet_version="1.0"
fi
case "$applet_version" in
    *[!0-9A-Za-z.+~-]*)
        printf 'The applet version %s has characters a file name should not have\n' "$applet_version" >&2
        exit 1
        ;;
esac
engine_version="$("$plister" get value "$framework/Info.plist" /CFBundleVersion 2>/dev/null)"
swift_version="$(/usr/bin/sed -n 's/^swift_version=//p' "$runtime_file")"
runtime_version="$(/usr/bin/sed -n 's/^runtime_line=//p' "$runtime_file")"
case "$engine_version" in
    ''|*[!0-9.]*)
        printf 'Cannot read the engine version (CFBundleVersion) from %s\n' "$framework/Info.plist" >&2
        exit 1
        ;;
esac
case "$swift_version$runtime_version" in
    *[!0-9.]*)
        printf 'Unexpected swift_version or runtime_line (the Swift runtime version) in %s\n' "$runtime_file" >&2
        exit 1
        ;;
esac
if [ -z "$swift_version" ] || [ -z "$runtime_version" ]; then
    printf 'No swift_version or runtime_line (the Swift runtime version) in %s\n' "$runtime_file" >&2
    exit 1
fi

# The architecture, from the executable's ELF header (e_machine, 2 bytes at offset 18)
machine="$(/usr/bin/od -An -t u2 -j 18 -N 2 -- "$executable" | /usr/bin/tr -d ' ')"
case "$machine" in
    183) architecture="aarch64"; deb_architecture="arm64" ;;
    62) architecture="x86_64"; deb_architecture="amd64" ;;
    *)
        printf 'Unknown ELF machine %s in %s\n' "${machine:-(none)}" "$executable" >&2
        exit 1
        ;;
esac
if [ -z "$release_url" ]; then
    release_url="https://github.com/abra-code/OMC/releases/download/v$engine_version"
fi
case "$release_url" in
    https://*) ;;
    *)
        printf 'The release URL must be https: %s\n' "$release_url" >&2
        exit 2
        ;;
esac

# The package files install.sh will look for (the names OMC's packaging scripts give them)
package_files="command-engine_${engine_version}-1_${deb_architecture}.deb command-engine-swift-${runtime_version}_${swift_version}-1_${deb_architecture}.deb command-engine-${engine_version}-1.${architecture}.rpm command-engine-swift-${runtime_version}-${swift_version}-1.${architecture}.rpm"
found_packages=""
if [ -n "$packages_folder" ]; then
    if [ ! -d "$packages_folder" ]; then
        printf 'No packages folder %s\n' "$packages_folder" >&2
        exit 1
    fi
    for file in $package_files; do
        if [ -f "$packages_folder/$file" ]; then
            found_packages="$found_packages $file"
        fi
    done
    if [ -z "$found_packages" ]; then
        printf 'None of these packages is in %s:\n  %s\n' "$packages_folder" "$package_files" >&2
        exit 1
    fi
fi

/bin/mkdir -p -- "$output"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot make %s\n' "$output" >&2
    exit 1
fi
output_given="$output"
output="$(CDPATH= cd -P -- "$output_given" && pwd)"
if [ -z "$output" ]; then
    printf 'Cannot enter %s\n' "$output_given" >&2
    exit 1
fi
work="$(/usr/bin/mktemp -d "$output/applet-archive.XXXXXX")"
status=$?
if [ "$status" -ne 0 ] || [ -z "$work" ]; then
    printf 'Cannot make a work folder in %s\n' "$output" >&2
    exit 1
fi
name="$applet_name-$applet_version-linux-$architecture"
folder="$work/$name"
/bin/mkdir -p "$folder"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot make %s\n' "$folder" >&2
    exit 1
fi
/bin/cp -a -- "$bundle" "$folder/$applet_name.app"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot copy %s\n' "$bundle" >&2
    exit 1
fi
/bin/cp -- "$installer" "$folder/install.sh"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot copy %s\n' "$installer" >&2
    exit 1
fi
/bin/chmod 755 "$folder/install.sh"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot set the mode of %s\n' "$folder/install.sh" >&2
    exit 1
fi
{
    printf 'applet_name=%s\n' "$applet_name"
    printf 'applet_version=%s\n' "$applet_version"
    printf 'bundle_identifier=%s\n' "$bundle_identifier"
    printf 'engine_version=%s\n' "$engine_version"
    printf 'runtime_version=%s\n' "$runtime_version"
    printf 'swift_version=%s\n' "$swift_version"
    printf 'architecture=%s\n' "$architecture"
    printf 'release_url=%s\n' "$release_url"
} > "$folder/install-info"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot write %s\n' "$folder/install-info" >&2
    exit 1
fi
if [ -n "$found_packages" ]; then
    : > "$folder/packages.sha256"
    for file in $found_packages; do
        sum="$(/usr/bin/sha256sum -- "$packages_folder/$file" | /usr/bin/cut -d ' ' -f 1)"
        if [ ${#sum} -ne 64 ]; then
            printf 'Cannot compute the SHA-256 of %s\n' "$packages_folder/$file" >&2
            exit 1
        fi
        printf '%s  %s\n' "$sum" "$file" >> "$folder/packages.sha256"
        if [ "$include_packages" -eq 1 ]; then
            /bin/mkdir -p "$folder/packages"
            /bin/cp -- "$packages_folder/$file" "$folder/packages/$file"
            status=$?
            if [ "$status" -ne 0 ]; then
                printf 'Cannot copy %s\n' "$packages_folder/$file" >&2
                exit 1
            fi
        fi
    done
fi
{
    printf '%s %s for Linux (%s)\n\n' "$applet_name" "$applet_version" "$architecture"
    printf 'To install, open a terminal in this folder and run:\n\n    ./install.sh\n\n'
    printf 'It installs the packages command-engine %s (the system libraries Command Engine applets\n' "$engine_version"
    printf 'need) and command-engine-swift-%s (the Swift runtime) when this machine does not have\n' "$runtime_version"
    printf 'them (with apt on Debian and Ubuntu, dnf on Fedora; it asks for your password), copies\n'
    printf '%s.app into ~/Applications, installs the libraries the applet needs, and adds it to\n' "$applet_name"
    printf 'the app list. ./install.sh --help lists its options.\n'
} > "$folder/README.txt"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot write %s\n' "$folder/README.txt" >&2
    exit 1
fi

archive="$output/$name.tar.gz"
# Owned by root in the archive: unpacked as root (then copied by install.sh with cp -a), the files
# do not belong to whatever user has the builder's uid on the target machine
/usr/bin/tar --owner=0 --group=0 --numeric-owner -C "$work" -czf "$archive" "$name"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot write %s (tar status %s); the folder is in %s\n' "$archive" "$status" "$work" >&2
    exit 1
fi
/bin/rm -rf -- "$work"
printf 'The archive: %s\n' "$archive"
exit 0
