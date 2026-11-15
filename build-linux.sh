#!/bin/bash
# build-linux.sh - builds OMC's Linux targets (Package.swift) with the flags the manifest cannot
# express: the toolchain's CoreFoundation headers, clang blocks, CF's Swift object layout, and C++
# without clang modules. Modeled on replay's build-linux.sh. Linux only.
#
# Usage: ./build-linux.sh [debug|release] [--jobs N] [--scratch-path DIR] [--product NAME]
#                         [--print-command] [-- swift-build-args...]
#   debug|release    configuration (default debug)
#   --scratch-path   build folder (default .build-linux/<machine>)
#   --product        build one product (default: all)
#   --print-command  print the swift build command and exit
#   SWIFT=/path/to/swift overrides the toolchain (default /usr/bin/swift)
# Before the build it makes ActionUI's Material Symbols icons (its Scripts/prepare-linux-symbols.sh).
# After a build of all products it builds ActionUI's ActionUIViewer and actionui-verify for Linux
# into the products folder (the helpers AppletBuilder carries), then makes the master applet,
# CommandApplet.app, there (Linux/make-applet-bundle.sh); not after a build of one product, which may
# lack the support tools the bundle carries.
# Exit status: 0 built, 1 setup failure or a helper that did not build, 2 bad arguments; a failed
# swift build of OMC exits with its status.

SCRIPT_DIR="$(CDPATH= cd -P -- "$(/usr/bin/dirname "$0")" && pwd)"
CONFIG="debug"
SCRATCH_PATH=""
JOBS=""
PRODUCT=""
PRINT_ONLY=0
EXTRA_ARGS=()
SWIFT="${SWIFT:-/usr/bin/swift}"

usage() {
    echo "Usage: $0 [debug|release] [--jobs N] [--scratch-path DIR] [--product NAME] [--print-command] [-- swift-build-args...]"
}

while [ $# -gt 0 ]; do
    case "$1" in
        debug|Debug) CONFIG="debug" ;;
        release|Release) CONFIG="release" ;;
        --jobs|-j|--scratch-path|--product)
            if [ $# -lt 2 ] || [ -z "$2" ]; then
                echo "Error: $1 needs a value" >&2
                exit 2
            fi
            case "$1" in
                --jobs|-j) JOBS="$2" ;;
                --scratch-path) SCRATCH_PATH="$2" ;;
                --product) PRODUCT="$2" ;;
            esac
            shift
            ;;
        --print-command) PRINT_ONLY=1 ;;
        --) shift; EXTRA_ARGS=("$@"); break ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Error: unknown argument $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

OS_NAME="$(/usr/bin/uname -s)"
if [ "$OS_NAME" != "Linux" ]; then
    echo "Error: build-linux.sh builds OMC for Linux; on macOS use the Xcode workspace (OMC.xcworkspace)." >&2
    exit 1
fi

if [ -z "$SCRATCH_PATH" ]; then
    MACHINE="$(/usr/bin/uname -m)"
    SCRATCH_PATH="$SCRIPT_DIR/.build-linux/$MACHINE"
fi

# The targets' source folders come from Linux/sources.txt; regenerate them so they cannot drift.
/bin/bash "$SCRIPT_DIR/Linux/make-shims.sh"
status=$?
if [ "$status" -ne 0 ]; then
    echo "Error: Linux/make-shims.sh failed with status $status" >&2
    exit 1
fi

TARGET_INFO="$("$SWIFT" -print-target-info 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
    echo "Error: '$SWIFT -print-target-info' failed with status $status:" >&2
    echo "$TARGET_INFO" >&2
    exit 1
fi
RESOURCE_PATH="$(printf '%s\n' "$TARGET_INFO" | /usr/bin/sed -n 's/.*"runtimeResourcePath"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | /usr/bin/head -n 1)"
if [ -z "$RESOURCE_PATH" ] || [ ! -f "$RESOURCE_PATH/CoreFoundation/CoreFoundation.h" ]; then
    echo "Error: CoreFoundation headers not found under the toolchain's runtime resource path '$RESOURCE_PATH'." >&2
    exit 1
fi

# ActionUI's checkout beside OMC (Package.swift depends on ../ActionUI, as the Xcode workspace does).
# Its C adapter header reaches Swift through a module map, which C++ compiled without modules does
# not read: the engine gets the header's folder directly.
ACTIONUI_ROOT="$(CDPATH= cd -P -- "$SCRIPT_DIR/../ActionUI" 2>/dev/null && pwd)"
if [ -z "$ACTIONUI_ROOT" ] || [ ! -f "$ACTIONUI_ROOT/ActionUICAdapter/include/ActionUIC.h" ]; then
    echo "Error: no ActionUI checkout with ActionUICAdapter/include/ActionUIC.h beside OMC ($SCRIPT_DIR/../ActionUI)." >&2
    exit 1
fi

# ActionUI shows SF Symbols on Linux as Material Symbols icons compiled into it (a GResource of
# symbolic SVGs and the name map, ActionUIAdwaita/CSymbolResource/generated, which git does not
# keep). ActionUI's own script makes them, downloading the font once (GitHub); it rewrites nothing
# that is current. Without it ActionUI builds with no icons, and every symbol in an applet's
# windows shows the missing-icon picture: that is said loudly, and the build goes on.
if [ "$PRINT_ONLY" -eq 0 ]; then
    /bin/bash "$ACTIONUI_ROOT/Scripts/prepare-linux-symbols.sh"
    status=$?
    if [ "$status" -ne 0 ]; then
        echo "Warning: ActionUI's Scripts/prepare-linux-symbols.sh failed (status $status): the applets will show no SF Symbols (see its messages above)." >&2
    fi
fi

# libadwaita's flags include GTK 4's and GLib's (the main-thread signal, the applet's app shell)
GLIB_CFLAGS="$(/usr/bin/pkg-config --cflags libadwaita-1)"
status=$?
if [ "$status" -ne 0 ] || [ -z "$GLIB_CFLAGS" ]; then
    echo "Error: pkg-config found no libadwaita-1 (install libadwaita-1-dev, which brings GTK 4 and GLib)." >&2
    exit 1
fi

# On Linux a CFSTR with non-ASCII text produces a broken string: its length is the UTF-8 byte count
# (replay's plan, fact 20). Reject such literals in the sources this build compiles.
NON_ASCII_CFSTR="$(LC_ALL=C /usr/bin/grep -rnE \
    --include='*.c' --include='*.cpp' --include='*.h' --include='*.mm' \
    --exclude-dir=Apple --exclude-dir=AbracodeTests --exclude-dir=.build --exclude-dir=.build-linux \
    'CFSTR\("([^"\\]|\\[^uUx])*([^ -~]|\\[uUx])' \
    "$SCRIPT_DIR/AbracodeFramework" "$SCRIPT_DIR/Common" "$SCRIPT_DIR/plister" "$SCRIPT_DIR/b64" \
    "$SCRIPT_DIR/filt" "$SCRIPT_DIR/loco" "$SCRIPT_DIR/omc_next_command" "$SCRIPT_DIR/omc_dialog_control")"
status=$?
if [ "$status" -eq 0 ]; then
    echo "Error: non-ASCII text in CFSTR literals, which is broken on Linux (use a string created at run time):" >&2
    echo "$NON_ASCII_CFSTR" >&2
    exit 1
fi
if [ "$status" -ne 1 ]; then
    echo "Error: the non-ASCII CFSTR check could not read the sources (grep status $status)." >&2
    exit 1
fi

SWIFT_ARGS=(build -c "$CONFIG" --package-path "$SCRIPT_DIR" --scratch-path "$SCRATCH_PATH")
if [ -n "$JOBS" ]; then
    SWIFT_ARGS+=(-j "$JOBS")
fi
if [ -n "$PRODUCT" ]; then
    SWIFT_ARGS+=(--product "$PRODUCT")
fi

# C and C++: CF headers as a system folder (their nullability warnings and narrowing conversions are
# silenced there only), clang blocks, CF's Swift object layout, and GLib, GTK 4 and libadwaita.
# ActionUIRemote's C header is generated by the build (OMCActionUIRemoteHost.cpp includes it, as Xcode's
# GENERATED_MODULEMAP_DIR gives it on macOS); Swift Build writes it to this folder of the scratch path
# before it compiles anything that depends on ActionUIRemote (probe actionui-remote-header).
GENERATED_HEADERS="$SCRATCH_PATH/out/Intermediates.noindex/GeneratedModuleMaps-linux-$(/usr/bin/uname -m)"
for flag in "-isystem$RESOURCE_PATH" -fblocks -fcf-runtime-abi=swift -DDEPLOYMENT_RUNTIME_SWIFT=1 $GLIB_CFLAGS \
            "-I$ACTIONUI_ROOT/ActionUICAdapter/include" "-I$GENERATED_HEADERS"; do
    SWIFT_ARGS+=(-Xcc "$flag" -Xcxx "$flag")
done

# Link: C and C++ executables are linked by clang, which does not know the Swift runtime's library
# folder (Foundation with CoreFoundation, dispatch, BlocksRuntime). The runtime path points there too
# until the packaging is decided (Private/linux-applet-packaging-analysis.md).
RUNTIME_LIB_PATH="$RESOURCE_PATH/linux"
if [ ! -d "$RUNTIME_LIB_PATH" ]; then
    echo "Error: the Swift runtime's library folder '$RUNTIME_LIB_PATH' does not exist." >&2
    exit 1
fi
# Package.swift reads it from the environment; -Xlinker flags here would reach only swiftc's links, not
# clang's. The manifest is evaluated every time (no cache), so a changed toolchain is picked up.
export OMC_SWIFT_RUNTIME_LIB="$RUNTIME_LIB_PATH"
SWIFT_ARGS+=(--manifest-cache none)

# C++ only: SwiftPM passes -fmodule-map-file without -fmodules on Linux, and clang then treats the
# headers those maps cover as modules nobody built (replay's plan, fact 6).
SWIFT_ARGS+=(-Xcxx -Xclang -Xcxx -fno-cxx-modules)

if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
    SWIFT_ARGS+=("${EXTRA_ARGS[@]}")
fi

if [ "$PRINT_ONLY" -eq 1 ]; then
    printf '%q ' "$SWIFT" "${SWIFT_ARGS[@]}"
    printf '\n'
    exit 0
fi

echo "Building OMC for Linux ($CONFIG) with $("$SWIFT" --version 2>&1 | /usr/bin/grep -v backtrac | /usr/bin/head -n 1)"
echo "Scratch path: $SCRATCH_PATH"
"$SWIFT" "${SWIFT_ARGS[@]}"
status=$?
if [ "$status" -ne 0 ]; then
    echo "Error: swift build failed with status $status" >&2
    exit "$status"
fi

# The master applet, CommandApplet.app, beside the built products (Linux/make-applet-bundle.sh): the
# newest engine in an applet bundle, as on macOS. Not when one product was built:
# the support tools it carries may not have been (CommandApplet alone does not build them).
if [ -n "$PRODUCT" ]; then
    exit 0
fi
PRODUCTS_PATH="$("$SWIFT" "${SWIFT_ARGS[@]}" --show-bin-path 2>/dev/null)"
status=$?
if [ "$status" -ne 0 ] || [ -z "$PRODUCTS_PATH" ] || [ ! -d "$PRODUCTS_PATH" ]; then
    echo "Error: the build's products folder could not be found (swift build --show-bin-path status $status)." >&2
    exit 1
fi

# ActionUI's own programs that applets carry as helpers (AppletBuilder's Contents/Helpers: the
# viewer for previews, the Swift verifier), built for Linux from their packages in the ActionUI
# checkout, each in a scratch folder of its own, and put beside the products:
# Linux/make-applet-bundle.sh gives an applet the Linux build of each macOS helper it carries.
for helper in ActionUIViewer:ActionUIViewer ActionUIVerifier:actionui-verify; do
    helper_package="$ACTIONUI_ROOT/Apps/${helper%%:*}"
    helper_product="${helper#*:}"
    helper_args=(build -c "$CONFIG" --package-path "$helper_package" --scratch-path "$SCRATCH_PATH/actionui-apps/${helper%%:*}" --product "$helper_product" --manifest-cache none)
    # As ActionUI builds them on Linux (Apps/ActionUIViewer/Package.swift): the root package's
    # file list is read anew (no manifest cache), and a tracked Package.resolved, which also pins
    # packages only macOS uses, is kept as it is
    if [ -f "$helper_package/Package.resolved" ]; then
        helper_args+=(--only-use-versions-from-resolved-file)
    fi
    echo "Building ActionUI's $helper_product for Linux"
    "$SWIFT" "${helper_args[@]}"
    status=$?
    if [ "$status" -ne 0 ]; then
        echo "Error: ActionUI's $helper_product did not build (swift build status $status, package $helper_package)." >&2
        exit 1
    fi
    helper_bin="$("$SWIFT" "${helper_args[@]}" --show-bin-path 2>/dev/null)"
    status=$?
    if [ "$status" -ne 0 ] || [ ! -x "$helper_bin/$helper_product" ]; then
        echo "Error: ActionUI's $helper_product was built but is not in its products folder ($helper_bin)." >&2
        exit 1
    fi
    /bin/cp -f -- "$helper_bin/$helper_product" "$PRODUCTS_PATH/$helper_product"
    status=$?
    if [ "$status" -ne 0 ]; then
        echo "Error: cannot copy $helper_product into $PRODUCTS_PATH." >&2
        exit 1
    fi
done

/bin/bash "$SCRIPT_DIR/Linux/make-applet-bundle.sh" "$PRODUCTS_PATH" "$SCRIPT_DIR/CommandApplet/Linux" "$PRODUCTS_PATH/CommandApplet.app"
status=$?
if [ "$status" -ne 0 ]; then
    echo "Error: CommandApplet.app could not be made (make-applet-bundle.sh status $status)." >&2
    exit 1
fi
echo "The master applet: $PRODUCTS_PATH/CommandApplet.app"

# The file manager plug-ins for applet services (Linux/FileManagerServices: the Services submenu and
# Launch for an applet bundle): their shared core, tested, then each plug-in this machine has the
# file manager and its development files for (skipped, and said so, otherwise: a build machine need
# not have any). NAUTILUS_HEADERS=<folder holding libnautilus-extension/> gives GNOME Files'
# headers where the libnautilus-extension-dev package is not installed.
services_args=("$PRODUCTS_PATH/file-manager-services")
if [ -n "$NAUTILUS_HEADERS" ]; then
    services_args+=(--nautilus-headers "$NAUTILUS_HEADERS")
fi
/bin/bash "$SCRIPT_DIR/Linux/FileManagerServices/build.sh" "${services_args[@]}"
status=$?
if [ "$status" -ne 0 ]; then
    echo "Error: the file manager plug-ins did not build or their tests failed (Linux/FileManagerServices/build.sh status $status)." >&2
    exit 1
fi
exit 0
