#!/bin/bash
# Linux/make-applet-bundle.sh - makes a Linux applet bundle from a build's products and an applet's
# sources, in the same Contents layout as a macOS applet, which Linux CoreFoundation reads with the
# executable in Contents/Linux (Platform/Linux/OMCEngineBundle.cpp, OMCAppletSupportURL.h). One
# layout on both systems: an applet's scripts find their files at the same paths
# ($OMC_APP_BUNDLE_PATH/Contents/Resources/...), and only the binaries differ (owner, 2026-11-12;
# a flat macOS app cannot be stapled):
#
#   <Name>.app/Contents/
#     Info.plist                    the applet's
#     Linux/<Name>                  the CommandApplet executable, renamed (the engine linked in)
#     Resources/                    Command.json, MainMenu.json, Base.lproj/..., Scripts/..., ...
#     Library/...                   an applet's own, as on macOS (not its macOS Python)
#     Library/Python/               with --python: a Linux Python (Python-Embedding's Linux build),
#                                   where the engine looks for the embedded interpreter
#                                   (Library/Python/bin/python3, as on macOS)
#     Frameworks/Abracode.framework/
#       Info.plist                  Linux/AbracodeFramework-Info.plist
#       omc_*.json                  the engine's built-in windows (AbracodeFramework/BuiltInDocuments)
#       <lang>.lproj/Private.strings  the engine's own texts (AbracodeFramework/*.lproj)
#       Support/                    the support tools (omc_dialog_control, omc_next_command, ...,
#                                   the defaults script from defaults/, the pasteboard script
#                                   from pasteboard/linux/, the open script from open/,
#                                   ActionUI's linux-app-entry.py from ../ActionUI/Scripts, and
#                                   command-services.py from Linux/)
#
# Usage: make-applet-bundle.sh [--python <Python folder>] <products folder> <applet sources>
#                              <output folder>/<Name>.app
#   The products folder is the build's (build-linux.sh), holding CommandApplet and the tools, and
#   the command-engine-runtime file build-linux.sh writes: every engine program copied into the
#   bundle (the executable, the support tools, the helpers) gets its bundle_runpath as its library
#   search path (/usr/lib/command-engine/swift-<line>, the Swift runtime package's folder).
#   --python copies a relocatable Linux Python (the folder holding bin/python3, as
#   Python-Embedding's build-embedded-python.sh makes it on Linux) into Contents/Library/Python.
#   It must be an ELF build for CommandApplet's architecture, and replaces any Library/Python the
#   applet sources have.
#   The applet sources are either
#   - a macOS applet bundle (a folder with Contents, e.g. one AppletBuilder made): everything in
#     its Contents is copied except what is macOS's: MacOS, Frameworks, _CodeSignature,
#     CodeResources, Library/Python (a macOS Python; --python gives a Linux one) and a Linux
#     folder from an earlier run; each helper program in Contents/Helpers is replaced by its
#     Linux build of the same name from the products folder (build-linux.sh puts ActionUI's
#     ActionUIViewer and actionui-verify there), or left out when there is none (a file there
#     that is not a program is copied as it is);
#   - or a source folder with no Contents: its Info.plist goes to Contents, a Library folder to
#     Contents/Library, everything else to Contents/Resources, except C and C++ sources and a
#     Frameworks folder.
#   The applet's Info.plist must name <Name> as its CFBundleExecutable. An existing bundle at the
#   output path is replaced.
# Exit status: 0 made, 1 failed, 2 bad arguments.

python_folder=""
if [ "$1" = "--python" ]; then
    if [ $# -lt 2 ] || [ -z "$2" ]; then
        printf -- '--python needs the Python folder\n' >&2
        exit 2
    fi
    python_folder="$2"
    shift 2
fi
products="$1"
source_folder="$2"
bundle="$3"
if [ -z "$products" ] || [ -z "$source_folder" ] || [ -z "$bundle" ] || [ $# -gt 3 ]; then
    printf 'Usage: %s [--python <Python folder>] <products folder> <applet source folder> <output>/<Name>.app\n' "$0" >&2
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
# Where the bundle's programs find the Swift runtime: build-linux.sh writes it beside the products
# (the command-engine-swift-<line> package's folder, and in a debug build the toolchain's after
# it). Each engine program copied into the bundle gets it in place of the folders the build left in
# it, which are the toolchain's and the build machine's own (set-elf-runpath.py).
bundle_runpath="$(/usr/bin/sed -n 's/^bundle_runpath=//p' "$products/command-engine-runtime" 2>/dev/null)"
if [ -z "$bundle_runpath" ]; then
    printf 'No bundle_runpath in %s: build the products with build-linux.sh\n' "$products/command-engine-runtime" >&2
    exit 1
fi
if [ ! -x /usr/bin/python3 ]; then
    printf 'No /usr/bin/python3, which set-elf-runpath.py needs\n' >&2
    exit 1
fi

# Gives the engine program at <file> (copied into the bundle) the bundle's runtime path, or fails
# the script
set_engine_runpath() { # <file>
    /usr/bin/python3 -I "$script_folder/set-elf-runpath.py" set "$1" "$bundle_runpath"
    local runpath_status=$?
    if [ "$runpath_status" -ne 0 ]; then
        printf 'Cannot set the runtime path of %s\n' "$1" >&2
        exit 1
    fi
}

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

# The Linux Python, checked before anything is removed: an ELF interpreter for the architecture of
# CommandApplet (bytes 0-3 the ELF magic, bytes 18-19 the machine; od reads through bin/python3's
# symbolic link), not inside the output, which is removed first, and not holding the output, which
# it is copied into
if [ -n "$python_folder" ]; then
    if [ ! -d "$python_folder" ] || [ ! -x "$python_folder/bin/python3" ]; then
        printf 'No Python at: %s (no executable bin/python3)\n' "$python_folder" >&2
        exit 2
    fi
    python_physical="$(CDPATH= cd -P -- "$python_folder" && pwd)"
    if [ -z "$python_physical" ]; then
        printf 'Cannot resolve the Python folder: %s\n' "$python_folder" >&2
        exit 1
    fi
    case "$python_physical/" in
        "$bundle_physical/"*) printf 'The Python folder is in the output: %s\n' "$python_folder" >&2; exit 2 ;;
    esac
    case "$bundle_physical/" in
        "$python_physical/"*) printf 'The output is in the Python folder: %s\n' "$bundle" >&2; exit 2 ;;
    esac
    # The interpreter itself must be inside the folder: a virtual environment's bin/python3 links
    # to the system's, and the bundle would not carry a Python of its own
    python_binary="$(/usr/bin/readlink -f -- "$python_folder/bin/python3")"
    case "$python_binary" in
        "$python_physical/"*) ;;
        *) printf 'The Python folder does not hold its interpreter: bin/python3 leads to %s, outside %s (a virtual environment?)\n' "$python_binary" "$python_physical" >&2; exit 1 ;;
    esac
    python_magic="$(/usr/bin/od -An -tx1 -N4 -- "$python_folder/bin/python3" | /usr/bin/tr -d ' \n')"
    if [ "$python_magic" != "7f454c46" ]; then
        printf 'The Python is not a Linux (ELF) build: %s\n' "$python_folder/bin/python3" >&2
        exit 1
    fi
    python_machine="$(/usr/bin/od -An -tx1 -j18 -N2 -- "$python_folder/bin/python3" | /usr/bin/tr -d ' \n')"
    applet_machine="$(/usr/bin/od -An -tx1 -j18 -N2 -- "$executable" | /usr/bin/tr -d ' \n')"
    if [ -z "$python_machine" ] || [ "$python_machine" != "$applet_machine" ]; then
        printf 'The Python is for another architecture than CommandApplet (ELF machine %s, not %s): %s\n' "$python_machine" "$applet_machine" "$python_folder" >&2
        exit 1
    fi
fi

# The applet's Info.plist must name the bundle's name as its executable, which CoreFoundation finds
# by that name. Checked before anything is removed or made, and read with the build's plister
# (Linux has no plutil).
source_info="$source_folder/Info.plist"
if [ -d "$source_folder/Contents" ]; then
    source_info="$source_folder/Contents/Info.plist"
fi
if [ ! -f "$source_info" ]; then
    printf 'The applet sources have no Info.plist: %s\n' "$source_info" >&2
    exit 1
fi
executable_name="$("$products/plister" get string "$source_info" /CFBundleExecutable 2>/dev/null)"
if [ -z "$executable_name" ]; then
    printf 'The applet'"'"'s Info.plist has no CFBundleExecutable, or plister cannot read it: %s\n' "$source_info" >&2
    exit 1
fi
if [ "$executable_name" != "$name" ]; then
    printf 'The applet'"'"'s Info.plist names "%s" as its CFBundleExecutable, not "%s" (the bundle'"'"'s name)\n' "$executable_name" "$name" >&2
    exit 1
fi

if [ -e "$bundle" ]; then
    /bin/rm -rf -- "$bundle"
    status=$?
    if [ "$status" -ne 0 ] || [ -e "$bundle" ]; then
        printf 'Cannot remove the existing bundle at: %s\n' "$bundle" >&2
        exit 1
    fi
fi
contents="$bundle/Contents"
framework="$contents/Frameworks/Abracode.framework"
/bin/mkdir -p "$framework/Support" "$contents/Linux" "$contents/Resources"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot make the bundle at: %s\n' "$bundle" >&2
    exit 1
fi

# Copies <item> to <destination>, or fails the script
copy_item() { # <item> <destination>
    /bin/cp -R -- "$1" "$2"
    local copy_status=$?
    if [ "$copy_status" -ne 0 ]; then
        printf 'Cannot copy %s into the bundle\n' "$1" >&2
        exit 1
    fi
}

# The applet's own files
if [ -d "$source_folder/Contents" ]; then
    for item in "$source_folder/Contents"/* ; do
        if [ ! -e "$item" ]; then
            continue # an empty Contents
        fi
        item_name="$(/usr/bin/basename -- "$item")"
        case "$item_name" in
            MacOS|Frameworks|_CodeSignature|CodeResources|Linux) continue ;;
            Helpers)
                # A macOS helper program gets its Linux build from the products, by name
                # (build-linux.sh puts ActionUI's viewer and verifier there); one with none is
                # left out, as a macOS program cannot run here
                for helper in "$item"/* ; do
                    if [ ! -e "$helper" ]; then
                        continue
                    fi
                    helper_name="$(/usr/bin/basename -- "$helper")"
                    # A file that is not a program (a license beside a helper) is copied as it is
                    if [ -f "$helper" ] && [ ! -x "$helper" ]; then
                        /bin/mkdir -p "$contents/Helpers"
                        status=$?
                        if [ "$status" -ne 0 ]; then
                            printf 'Cannot make %s\n' "$contents/Helpers" >&2
                            exit 1
                        fi
                        copy_item "$helper" "$contents/Helpers/$helper_name"
                        continue
                    fi
                    if [ ! -f "$products/$helper_name" ] || [ ! -x "$products/$helper_name" ]; then
                        printf 'Note: no Linux build of the helper %s in %s: the Linux applet has none\n' "$helper_name" "$products" >&2
                        continue
                    fi
                    /bin/mkdir -p "$contents/Helpers"
                    status=$?
                    if [ "$status" -ne 0 ]; then
                        printf 'Cannot make %s\n' "$contents/Helpers" >&2
                        exit 1
                    fi
                    copy_item "$products/$helper_name" "$contents/Helpers/$helper_name"
                    set_engine_runpath "$contents/Helpers/$helper_name"
                done
                ;;
            Resources)
                for resource in "$item"/* ; do
                    if [ -e "$resource" ]; then
                        copy_item "$resource" "$contents/Resources/"
                    fi
                done
                ;;
            Library)
                for library_item in "$item"/* ; do
                    if [ ! -e "$library_item" ]; then
                        continue
                    fi
                    case "$(/usr/bin/basename -- "$library_item")" in
                        Python) continue ;; # a macOS Python
                    esac
                    /bin/mkdir -p "$contents/Library"
                    status=$?
                    if [ "$status" -ne 0 ]; then
                        printf 'Cannot make %s\n' "$contents/Library" >&2
                        exit 1
                    fi
                    copy_item "$library_item" "$contents/Library/"
                done
                ;;
            *) copy_item "$item" "$contents/$item_name" ;;
        esac
    done
else
    for item in "$source_folder"/* ; do
        if [ ! -e "$item" ]; then
            continue # an empty source folder
        fi
        item_name="$(/usr/bin/basename -- "$item")"
        case "$item_name" in
            *.c|*.cpp|*.h|Frameworks) continue ;;
            Info.plist) copy_item "$item" "$contents/Info.plist" ;;
            Library) copy_item "$item" "$contents/Library" ;; # beside Resources, as on macOS
            *) copy_item "$item" "$contents/Resources/$item_name" ;;
        esac
    done
fi
if [ ! -f "$contents/Info.plist" ]; then
    printf 'The applet sources have no Info.plist: %s\n' "$source_folder" >&2
    exit 1
fi

# The Linux Python, in place of any the sources had (a source folder's Library is copied whole).
# cp -R copies symbolic links as links (bin/python3 -> python3.N).
if [ -n "$python_folder" ]; then
    if [ -e "$contents/Library/Python" ]; then
        /bin/rm -rf -- "$contents/Library/Python"
        status=$?
        if [ "$status" -ne 0 ] || [ -e "$contents/Library/Python" ]; then
            printf 'Cannot replace the Library/Python of the applet sources\n' >&2
            exit 1
        fi
    fi
    /bin/mkdir -p "$contents/Library"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'Cannot make %s\n' "$contents/Library" >&2
        exit 1
    fi
    # From the resolved folder: given a link to the folder, cp -R would copy the link
    copy_item "$python_physical" "$contents/Library/Python"
fi

# The executable, under the applet's name
/bin/cp -- "$executable" "$contents/Linux/$name"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot copy the executable into the bundle\n' >&2
    exit 1
fi
set_engine_runpath "$contents/Linux/$name"
/bin/chmod 755 "$contents/Linux/$name"
# The applet's install script (checks what it needs, adds it to the desktop): AppletBuilder's, which
# AppletBuilder's own build copies into the applets it makes the same way (lib.build.sh)
installer_source="$omc_root/Distribution/AppletBuilder.app/Contents/Resources/Linux/install-applet.sh"
/bin/cp -- "$installer_source" "$contents/Linux/install-applet.sh"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot copy %s into the bundle\n' "$installer_source" >&2
    exit 1
fi
/bin/chmod 755 "$contents/Linux/install-applet.sh"
if [ -d "$contents/Resources/Scripts" ]; then
    /usr/bin/find "$contents/Resources/Scripts" -type f -exec /bin/chmod 755 {} +
fi

# The engine's framework: its Info.plist, built-in windows, texts and support tools. The Info.plist
# gets the engine's version (CFBundleVersion) from Common/OmcVersion.xcconfig, as the macOS
# framework's does: AppletBuilder compares it to update an applet's framework on a build.
omc_version="$(/usr/bin/sed -n 's/^OMC_BUNDLE_VERSION *= *\([0-9][0-9.]*\) *$/\1/p' "$omc_root/Common/OmcVersion.xcconfig")"
if [ -z "$omc_version" ]; then
    printf 'Cannot read OMC_BUNDLE_VERSION from %s\n' "$omc_root/Common/OmcVersion.xcconfig" >&2
    exit 1
fi
/usr/bin/sed "s/\${OMC_BUNDLE_VERSION}/$omc_version/" "$script_folder/AbracodeFramework-Info.plist" > "$framework/Info.plist"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot write the framework Info.plist\n' >&2
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
    set_engine_runpath "$framework/Support/$tool"
done
# The applets' settings tool, a script (defaults/defaults), as on macOS
/bin/cp -- "$omc_root/defaults/defaults" "$framework/Support/defaults"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot copy the defaults tool into the framework\n' >&2
    exit 1
fi
/bin/chmod 755 "$framework/Support/defaults"
# The named pasteboards, a script on Linux (pasteboard/linux/pasteboard; macOS has the Objective-C tool)
/bin/cp -- "$omc_root/pasteboard/linux/pasteboard" "$framework/Support/pasteboard"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot copy the pasteboard tool into the framework\n' >&2
    exit 1
fi
/bin/chmod 755 "$framework/Support/pasteboard"
# Opening files, folders and applications, a script on both systems (open/open)
/bin/cp -- "$omc_root/open/open" "$framework/Support/open"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot copy the open tool into the framework\n' >&2
    exit 1
fi
/bin/chmod 755 "$framework/Support/open"
# The desktop's app list: ActionUI's linux-app-entry.py, from the ActionUI checkout beside OMC that
# the Linux build links (build-linux.sh). It writes an applet's desktop entry and installs its icon
# from Contents/Info.plist; AppletBuilder runs it after a build, as macOS registers the applet
# with Launch Services.
app_entry_source="$omc_root/../ActionUI/Scripts/linux-app-entry.py"
/bin/cp -- "$app_entry_source" "$framework/Support/linux-app-entry.py"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot copy %s into the framework (ActionUI is expected beside OMC)\n' "$app_entry_source" >&2
    exit 1
fi
/bin/chmod 755 "$framework/Support/linux-app-entry.py"
# The file managers' Services menu: command-services.py lists an applet's file services (NSServices)
# for the OMC file manager plug-ins; AppletBuilder runs it beside linux-app-entry.py, whose
# Info.plist reading and type table it uses (it finds that file beside itself)
/bin/cp -- "$script_folder/command-services.py" "$framework/Support/command-services.py"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot copy %s into the framework\n' "$script_folder/command-services.py" >&2
    exit 1
fi
/bin/chmod 755 "$framework/Support/command-services.py"
exit 0
