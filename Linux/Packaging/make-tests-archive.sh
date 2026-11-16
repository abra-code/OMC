#!/bin/bash
# Linux/Packaging/make-tests-archive.sh - makes the tests archive of an engine build: the Linux test
# programs and test runners with everything they read, so that a later Swift runtime can be checked
# against this release's engine without its source tree or toolchain (design:
# Private/linux-applet-install-design.md, "Decisions, 2026-11-16", item 8: the second runtime gate).
# The release process publishes the archive beside the release; check-swift-runtime-tests.sh runs the
# archives of earlier releases against a candidate runtime.
#
# The archive, command-engine-tests-<engine version>-<debug|release>-<architecture>.tar.gz, holds one
# folder of the same name:
#   products/   the build's programs as the tests use them: CommandApplet and its support tools,
#               ActionUI's helpers, OMCLinuxUITests, OMCLinuxPortTests, the master applet
#               CommandApplet.app, command-engine-runtime; each loose program's library search path is
#               the bundles' (bundle_runpath: the runtime package's folder), not the build folder's;
#               Frameworks/Command.framework is a link into CommandApplet.app (OMCLinuxUITests looks
#               for it beside itself)
#   OMC/        the parts of the source tree the test runners read (Linux/Tests, make-applet-bundle.sh
#               and what it copies into a bundle, the integration-test fixture and harness)
#   ActionUI/   what bundles and runners use of ActionUI: linux-app-entry.py and the remote bridge's
#               shell client (ActionUIRemote/Shell, which the Linux client sources files from)
#   run-tests.sh  runs them all (Linux/Packaging/run-engine-tests.sh)
#
# Usage: make-tests-archive.sh <products folder> <output folder>
#   The products folder is build-linux.sh's after a build of all products (Debug-linux-<arch> or
#   Release-linux-<arch>); only a debug build has the integration-test surface (OMCITest).
#   ActionUI is expected beside OMC, as the build finds it.
# Needs python3 (set-elf-runpath.py) and tar. Exit status: 0 made, 1 failed, 2 bad arguments.

umask 022

products="$1"
output="$2"
if [ -z "$products" ] || [ -z "$output" ] || [ $# -ne 2 ]; then
    printf 'Usage: %s <products folder> <output folder>\n' "$0" >&2
    exit 2
fi
products_given="$products"
products="$(CDPATH= cd -P -- "$products_given" 2>/dev/null && pwd)"
if [ -z "$products" ]; then
    printf 'No products folder at %s\n' "$products_given" >&2
    exit 1
fi
script_folder="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
omc_root="$(CDPATH= cd -P -- "$script_folder/../.." && pwd)"
actionui_root="$(CDPATH= cd -P -- "$omc_root/../ActionUI" 2>/dev/null && pwd)"
if [ -z "$actionui_root" ]; then
    printf 'No ActionUI checkout beside %s\n' "$omc_root" >&2
    exit 1
fi

case "${products##*/}" in
    Debug-*) configuration="debug" ;;
    Release-*) configuration="release" ;;
    *)
        printf 'Cannot tell the configuration of %s (a Debug-linux-<arch> or Release-linux-<arch> folder)\n' "$products" >&2
        exit 1
        ;;
esac
runtime_file="$products/command-engine-runtime"
bundle_runpath="$(/usr/bin/sed -n 's/^bundle_runpath=//p' "$runtime_file" 2>/dev/null)"
if [ -z "$bundle_runpath" ]; then
    printf 'No bundle_runpath in %s: build the products with build-linux.sh\n' "$runtime_file" >&2
    exit 1
fi
engine_version="$(/usr/bin/sed -n 's/^OMC_BUNDLE_VERSION *= *\([0-9][0-9.]*\) *$/\1/p' "$omc_root/Common/OmcVersion.xcconfig")"
if [ -z "$engine_version" ]; then
    printf 'Cannot read OMC_BUNDLE_VERSION from %s\n' "$omc_root/Common/OmcVersion.xcconfig" >&2
    exit 1
fi
architecture="$(/usr/bin/uname -m)"
if [ -z "$architecture" ]; then
    printf 'uname -m gave nothing\n' >&2
    exit 1
fi
if [ ! -x /usr/bin/python3 ] || [ ! -x /usr/bin/tar ]; then
    printf 'Needs /usr/bin/python3 and /usr/bin/tar\n' >&2
    exit 1
fi

# The programs, as build-linux.sh leaves them; the helpers are optional, as make-applet-bundle.sh has them
programs="CommandApplet omc_dialog_control omc_next_command plister b64 filt loco OMCLinuxUITests OMCLinuxPortTests"
helpers="ActionUIViewer actionui-verify"
for program in $programs; do
    if [ ! -x "$products/$program" ]; then
        printf 'No %s in %s: build all products with build-linux.sh\n' "$program" "$products" >&2
        exit 1
    fi
done
if [ ! -d "$products/CommandApplet.app/Contents/Frameworks/Command.framework" ]; then
    printf 'No CommandApplet.app in %s: build all products with build-linux.sh\n' "$products" >&2
    exit 1
fi

# The source tree's parts, from the OMC root and from ActionUI's
omc_parts="Linux/make-applet-bundle.sh Linux/set-elf-runpath.py Linux/command-services.py Linux/CommandFramework-Info.plist Linux/Tests Common/OmcVersion.xcconfig CommandFramework/BuiltInDocuments defaults/defaults pasteboard/linux/pasteboard open/open Distribution/AppletBuilder.app/Contents/Resources/Linux Distribution/AppletBuilder.app/Contents/Resources/Agents Distribution/AppletBuilder.app/Contents/Library/Packages Tools/omcitest_tests"
for strings_folder in "$omc_root/CommandFramework"/*.lproj; do
    if [ -d "$strings_folder" ]; then
        omc_parts="$omc_parts CommandFramework/${strings_folder##*/}"
    fi
done
actionui_parts="Scripts/linux-app-entry.py ActionUIRemote/Shell"
for part in $omc_parts; do
    if [ ! -e "$omc_root/$part" ]; then
        printf 'No %s in %s\n' "$part" "$omc_root" >&2
        exit 1
    fi
done
for part in $actionui_parts; do
    if [ ! -e "$actionui_root/$part" ]; then
        printf 'No %s in %s\n' "$part" "$actionui_root" >&2
        exit 1
    fi
done
if [ ! -f "$script_folder/run-engine-tests.sh" ]; then
    printf 'No %s\n' "$script_folder/run-engine-tests.sh" >&2
    exit 1
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
work="$(/usr/bin/mktemp -d "$output/tests-archive.XXXXXX")"
status=$?
if [ "$status" -ne 0 ] || [ -z "$work" ]; then
    printf 'Cannot make a work folder in %s\n' "$output" >&2
    exit 1
fi
name="command-engine-tests-$engine_version-$configuration-$architecture"
kit="$work/$name"
/bin/mkdir -p "$kit/products/Frameworks" "$kit/OMC" "$kit/ActionUI"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot make the folders in %s\n' "$kit" >&2
    exit 1
fi

# Products: the loose programs get the bundles' library search path, so they find the runtime package
# (or the folder a check puts first on LD_LIBRARY_PATH), never this build machine's folders
for program in $programs $helpers; do
    if [ ! -x "$products/$program" ]; then
        continue # an optional helper this build has not got
    fi
    /bin/cp -- "$products/$program" "$kit/products/$program"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'Cannot copy %s\n' "$products/$program" >&2
        exit 1
    fi
    /usr/bin/python3 -I "$omc_root/Linux/set-elf-runpath.py" set "$kit/products/$program" "$bundle_runpath"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'Cannot set the library search path of %s\n' "$kit/products/$program" >&2
        exit 1
    fi
done
/bin/cp -- "$runtime_file" "$kit/products/command-engine-runtime"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot copy %s\n' "$runtime_file" >&2
    exit 1
fi
/bin/cp -a -- "$products/CommandApplet.app" "$kit/products/CommandApplet.app"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot copy %s\n' "$products/CommandApplet.app" >&2
    exit 1
fi
/bin/ln -s ../CommandApplet.app/Contents/Frameworks/Command.framework "$kit/products/Frameworks/Command.framework"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot link %s\n' "$kit/products/Frameworks/Command.framework" >&2
    exit 1
fi

# The source parts, at the same places relative to each other as in the checkouts
/usr/bin/tar -C "$omc_root" -cf - $omc_parts | /usr/bin/tar -C "$kit/OMC" -xf -
tar_status="${PIPESTATUS[0]} ${PIPESTATUS[1]}"
if [ "$tar_status" != "0 0" ]; then
    printf 'Cannot copy the OMC parts (tar status %s)\n' "$tar_status" >&2
    exit 1
fi
/usr/bin/tar -C "$actionui_root" -cf - $actionui_parts | /usr/bin/tar -C "$kit/ActionUI" -xf -
tar_status="${PIPESTATUS[0]} ${PIPESTATUS[1]}"
if [ "$tar_status" != "0 0" ]; then
    printf 'Cannot copy the ActionUI parts (tar status %s)\n' "$tar_status" >&2
    exit 1
fi
/bin/cp -- "$script_folder/run-engine-tests.sh" "$kit/run-tests.sh"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot copy %s\n' "$script_folder/run-engine-tests.sh" >&2
    exit 1
fi
/bin/chmod 755 "$kit/run-tests.sh"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot set the mode of %s\n' "$kit/run-tests.sh" >&2
    exit 1
fi
printf 'engine_version=%s\nconfiguration=%s\narchitecture=%s\n' "$engine_version" "$configuration" "$architecture" > "$kit/tests-archive-info"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot write %s\n' "$kit/tests-archive-info" >&2
    exit 1
fi

archive="$output/$name.tar.gz"
/usr/bin/tar -C "$work" -czf "$archive" "$name"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot write %s (tar status %s); the folder is in %s\n' "$archive" "$status" "$work" >&2
    exit 1
fi
/bin/rm -rf -- "$work"
printf 'The tests archive: %s\n' "$archive"
exit 0
