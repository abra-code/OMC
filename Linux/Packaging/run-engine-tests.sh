#!/bin/bash
# Linux/Packaging/run-engine-tests.sh - runs the Linux tests of an engine build from its tests archive
# (make-tests-archive.sh copies this script into the archive as run-tests.sh), optionally on another
# Swift runtime than the one the programs were built with: the second runtime gate (design:
# Private/linux-applet-install-design.md, "Decisions, 2026-11-16", item 8; check-swift-runtime-tests.sh
# runs it for each earlier release).
#
# Runs, from the archive's folder: OMCLinuxPortTests, OMCLinuxUITests, the applet launch test, the
# embedded Python applet test (with --python), and the integration tests (debug builds only: release
# builds have no test surface). With --runtime the folder goes first on LD_LIBRARY_PATH, which the
# loader searches before the programs' own search path (RUNPATH), so every program the tests start
# loads the Swift runtime from there; the script checks that CommandApplet does.
#
# Usage: run-tests.sh [--runtime <folder holding libswiftCore.so>] [--python <Linux Python folder>]
#   Without --runtime the programs use the runtime package of their own line
#   (/usr/lib/command-engine/swift-<line>), or a toolchain's /usr/lib/swift/linux after it.
#   Needs a desktop session (on an agent-vm box: GNOME's Wayland socket, set up below when
#   WAYLAND_DISPLAY is unset), python3, and for the integration tests OpenBSD netcat and timeout.
# Exit status: 0 all passed, 1 a test failed, 2 bad arguments.

runtime=""
python_folder=""
while [ $# -gt 0 ]; do
    case "$1" in
        --runtime|--python)
            if [ $# -lt 2 ] || [ -z "$2" ]; then
                printf 'run-tests.sh: %s needs a folder\n' "$1" >&2
                exit 2
            fi
            if [ "$1" = "--runtime" ]; then
                runtime="$2"
            else
                python_folder="$2"
            fi
            shift 2
            ;;
        *)
            printf 'Usage: %s [--runtime <folder holding libswiftCore.so>] [--python <Linux Python folder>]\n' "$0" >&2
            exit 2
            ;;
    esac
done

kit="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
products="$kit/products"
tests="$kit/OMC/Linux/Tests"
configuration="$(/usr/bin/sed -n 's/^configuration=//p' "$kit/tests-archive-info" 2>/dev/null)"
engine_version="$(/usr/bin/sed -n 's/^engine_version=//p' "$kit/tests-archive-info" 2>/dev/null)"
if [ -z "$configuration" ] || [ ! -x "$products/CommandApplet" ]; then
    printf 'run-tests.sh: %s is not an unpacked tests archive (no tests-archive-info or products)\n' "$kit" >&2
    exit 2
fi

if [ -n "$runtime" ]; then
    runtime_given="$runtime"
    runtime="$(CDPATH= cd -P -- "$runtime_given" 2>/dev/null && pwd)"
    if [ -z "$runtime" ] || [ ! -f "$runtime/libswiftCore.so" ]; then
        printf 'run-tests.sh: no libswiftCore.so in %s\n' "$runtime_given" >&2
        exit 2
    fi
    export LD_LIBRARY_PATH="$runtime"
fi
if [ -n "$python_folder" ] && [ ! -x "$python_folder/bin/python3" ]; then
    printf 'run-tests.sh: no bin/python3 in %s\n' "$python_folder" >&2
    exit 2
fi

uid="$(/usr/bin/id -u)"
if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ]; then
    export XDG_RUNTIME_DIR="/run/user/$uid"
    export WAYLAND_DISPLAY=wayland-0
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
fi
export SWIFT_BACKTRACE=enable=no

results=""
failed=0
record() { # <name> <status>
    if [ "$2" -eq 0 ]; then
        results="${results}ok   $1
"
    else
        results="${results}FAIL $1 (status $2)
"
        failed=$((failed + 1))
    fi
}

# Which runtime the engine loads: with --runtime it has to be that folder's
loaded="$(/usr/bin/ldd "$products/CommandApplet" 2>/dev/null | /usr/bin/awk '$1 == "libswiftCore.so" { print $3 }')"
printf 'Engine %s (%s), Swift runtime loaded from: %s\n' "$engine_version" "$configuration" "${loaded:-nowhere}"
if [ -z "$loaded" ]; then
    record "CommandApplet finds a Swift runtime" 1
elif [ -n "$runtime" ] && [ "$loaded" != "$runtime/libswiftCore.so" ]; then
    printf 'CommandApplet loads %s, not the runtime given (%s)\n' "$loaded" "$runtime"
    record "CommandApplet loads the runtime given" 1
fi

printf '\n== OMCLinuxPortTests ==\n'
"$products/OMCLinuxPortTests" "$products/omc_dialog_control"
record "OMCLinuxPortTests" $?

printf '\n== OMCLinuxUITests ==\n'
"$products/OMCLinuxUITests"
record "OMCLinuxUITests" $?

printf '\n== OMCAppletLaunchTest ==\n'
/bin/bash "$tests/OMCAppletLaunchTest/run.sh" "$products"
record "OMCAppletLaunchTest" $?

if [ -n "$python_folder" ]; then
    printf '\n== OMCPythonAppletTest ==\n'
    /bin/bash "$tests/OMCPythonAppletTest/run.sh" "$products" "$python_folder"
    record "OMCPythonAppletTest" $?
fi

if [ "$configuration" = "debug" ]; then
    printf '\n== OMCITest ==\n'
    /bin/bash "$tests/OMCITest/run.sh" "$products"
    record "OMCITest" $?
fi

printf '\n== Engine %s (%s) on %s ==\n%s' "$engine_version" "$configuration" "${runtime:-its own runtime}" "$results"
if [ "$failed" -ne 0 ]; then
    exit 1
fi
exit 0
