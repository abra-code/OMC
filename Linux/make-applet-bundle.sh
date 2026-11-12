#!/bin/bash
# Linux/make-applet-bundle.sh - makes a Linux applet bundle from a build's products and an applet's
# source folder, in the flat layout the Linux engine reads (Platform/Linux/OMCEngineBundle.cpp,
# Private/linux-applet-packaging-analysis.md):
#
#   <Name>.app/
#     <Name>                        the CommandApplet executable, renamed (the engine linked in)
#     Info.plist, Command.json, MainMenu.json, Base.lproj/..., Scripts/...   the applet's own files
#     Frameworks/Abracode.framework/
#       Info.plist                  Linux/AbracodeFramework-Info.plist
#       omc_*.json                  the engine's built-in windows (AbracodeFramework/BuiltInDocuments)
#       <lang>.lproj/Private.strings  the engine's own texts (AbracodeFramework/*.lproj)
#       Support/                    the support tools (omc_dialog_control, omc_next_command, ...)
#
# Usage: make-applet-bundle.sh <products folder> <applet source folder> <output folder>/<Name>.app
#   The products folder is the build's (build-linux.sh), holding CommandApplet and the tools. Every
#   file and folder in the source folder is copied, except C and C++ sources and a Frameworks
#   folder; the applet's Info.plist must name <Name> as its CFBundleExecutable. An existing bundle
#   at the output path is replaced.
# Exit status: 0 made, 1 failed, 2 bad arguments.

products="$1"
source_folder="$2"
bundle="$3"
if [ -z "$products" ] || [ -z "$source_folder" ] || [ -z "$bundle" ]; then
    printf 'Usage: %s <products folder> <applet source folder> <output>/<Name>.app\n' "$0" >&2
    exit 2
fi
case "$bundle" in
    *.app) ;;
    *) printf 'The output must be a folder named <Name>.app: %s\n' "$bundle" >&2; exit 2 ;;
esac
name="$(/usr/bin/basename -- "$bundle" .app)"
if [ -z "$name" ] || [ "$name" = "." ] || [ "$name" = ".." ]; then
    printf 'No applet name in the output path: %s\n' "$bundle" >&2
    exit 2
fi
if [ ! -d "$source_folder" ]; then
    printf 'No applet source folder at: %s\n' "$source_folder" >&2
    exit 2
fi

script_folder="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
omc_root="$(CDPATH= cd -P -- "$script_folder/.." && pwd)"
executable="$products/CommandApplet"
if [ ! -x "$executable" ]; then
    printf 'No CommandApplet executable in the products folder: %s\n' "$products" >&2
    exit 1
fi
tools="omc_dialog_control omc_next_command plister b64 filt loco"
for tool in $tools; do
    if [ ! -x "$products/$tool" ]; then
        printf 'No %s in the products folder: %s\n' "$tool" "$products" >&2
        exit 1
    fi
done

# The output is removed and then filled from the source folder, so neither may hold the other
bundle_parent="$(/usr/bin/dirname -- "$bundle")"
/bin/mkdir -p -- "$bundle_parent"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot make the folder for the bundle: %s\n' "$bundle_parent" >&2
    exit 1
fi
source_physical="$(CDPATH= cd -P -- "$source_folder" && pwd)"
bundle_parent_physical="$(CDPATH= cd -P -- "$bundle_parent" && pwd)"
if [ -z "$source_physical" ] || [ -z "$bundle_parent_physical" ]; then
    printf 'Cannot resolve the source folder or the output folder\n' >&2
    exit 1
fi
bundle_physical="$bundle_parent_physical/$name.app"
case "$bundle_physical/" in
    "$source_physical/"*) printf 'The output is in the applet source folder: %s\n' "$bundle" >&2; exit 2 ;;
esac
case "$source_physical/" in
    "$bundle_physical/"*) printf 'The applet source folder is in the output: %s\n' "$source_folder" >&2; exit 2 ;;
esac

if [ -e "$bundle" ]; then
    /bin/rm -rf -- "$bundle"
    status=$?
    if [ "$status" -ne 0 ] || [ -e "$bundle" ]; then
        printf 'Cannot remove the existing bundle at: %s\n' "$bundle" >&2
        exit 1
    fi
fi
framework="$bundle/Frameworks/Abracode.framework"
/bin/mkdir -p "$framework/Support"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot make the bundle at: %s\n' "$bundle" >&2
    exit 1
fi

# The applet's own files
for item in "$source_folder"/* ; do
    if [ ! -e "$item" ]; then
        continue # an empty source folder
    fi
    item_name="$(/usr/bin/basename -- "$item")"
    case "$item_name" in
        *.c|*.cpp|*.h|Frameworks) continue ;;
    esac
    /bin/cp -R -- "$item" "$bundle/$item_name"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'Cannot copy %s into the bundle\n' "$item" >&2
        exit 1
    fi
done
if [ ! -f "$bundle/Info.plist" ]; then
    printf 'The applet source folder has no Info.plist: %s\n' "$source_folder" >&2
    exit 1
fi

# The executable, under the applet's name
/bin/cp -- "$executable" "$bundle/$name"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot copy the executable into the bundle\n' >&2
    exit 1
fi
/bin/chmod 755 "$bundle/$name"
if [ -d "$bundle/Scripts" ]; then
    /usr/bin/find "$bundle/Scripts" -type f -exec /bin/chmod 755 {} +
fi

# The engine's framework: its Info.plist, built-in windows, texts and support tools
/bin/cp -- "$script_folder/AbracodeFramework-Info.plist" "$framework/Info.plist"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot copy the framework Info.plist\n' >&2
    exit 1
fi
for document in "$omc_root/AbracodeFramework/BuiltInDocuments"/*.json; do
    /bin/cp -- "$document" "$framework/"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'Cannot copy %s into the framework\n' "$document" >&2
        exit 1
    fi
done
for strings_folder in "$omc_root/AbracodeFramework"/*.lproj; do
    if [ ! -f "$strings_folder/Private.strings" ]; then
        continue
    fi
    language_folder="$framework/$(/usr/bin/basename -- "$strings_folder")"
    /bin/mkdir -p "$language_folder"
    /bin/cp -- "$strings_folder/Private.strings" "$language_folder/Private.strings"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'Cannot copy %s into the framework\n' "$strings_folder/Private.strings" >&2
        exit 1
    fi
done
for tool in $tools; do
    /bin/cp -- "$products/$tool" "$framework/Support/$tool"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'Cannot copy the tool %s into the framework\n' "$tool" >&2
        exit 1
    fi
done
exit 0
