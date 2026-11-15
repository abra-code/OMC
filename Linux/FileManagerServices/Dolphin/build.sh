#!/bin/bash
# Linux/FileManagerServices/Dolphin/build.sh - builds the Dolphin (KDE Plasma) plug-in for Command
# applet services (command-services-dolphin.so, a KIO file item action plug-in, with the shared core
# in ..) and its test program with CMake (CMakeLists.txt beside it), then runs the test on Qt's
# offscreen platform. ../build.sh runs it after the core's own test, when the machine has KIO 6's
# development files.
#
# Usage: build.sh <output folder>
#
# Needs CMake, C and C++ compilers, extra-cmake-modules, Qt 6 and KIO 6 development files (Debian:
# cmake extra-cmake-modules qt6-base-dev libkf6kio-dev) and GLib's (libglib2.0-dev).
# Exit status: 0 built and tests passed, 1 a step failed, 2 bad arguments.

out="$1"
if [ -z "$out" ]; then
    printf 'Usage: %s <output folder>\n' "$0" >&2
    exit 2
fi
here="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
/bin/mkdir -p "$out"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'cannot make %s\n' "$out" >&2
    exit 1
fi

cmake=/usr/bin/cmake
if [ ! -x "$cmake" ]; then
    printf 'no CMake (install cmake)\n' >&2
    exit 1
fi
"$cmake" -S "$here" -B "$out/build" -DCMAKE_BUILD_TYPE=Release > "$out/configure.log" 2>&1
status=$?
if [ "$status" -ne 0 ]; then
    /usr/bin/tail -n 20 "$out/configure.log" >&2
    printf 'the plug-in could not be configured (see %s; install extra-cmake-modules qt6-base-dev libkf6kio-dev)\n' "$out/configure.log" >&2
    exit 1
fi
"$cmake" --build "$out/build" --parallel > "$out/build.log" 2>&1
status=$?
if [ "$status" -ne 0 ]; then
    /usr/bin/tail -n 30 "$out/build.log" >&2
    printf 'the plug-in did not build (see %s)\n' "$out/build.log" >&2
    exit 1
fi
plugin="$(/usr/bin/find "$out/build" -name command-services-dolphin.so -type f | /usr/bin/head -n 1)"
if [ -z "$plugin" ]; then
    printf 'the build made no command-services-dolphin.so\n' >&2
    exit 1
fi
/bin/cp -- "$plugin" "$out/command-services-dolphin.so"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'cannot copy %s to %s\n' "$plugin" "$out" >&2
    exit 1
fi
# The plug-in loaded as Dolphin loads it, asked for its actions with real files
QT_QPA_PLATFORM=offscreen "$out/build/command-services-dolphin-test" "$out/command-services-dolphin.so"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'the plug-in tests failed\n' >&2
    exit 1
fi
printf 'built %s\n' "$out/command-services-dolphin.so"
exit 0
