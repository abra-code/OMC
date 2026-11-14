#!/bin/bash
# Linux/NautilusServices/build.sh - builds the GNOME Files plug-in for Command applet services
# (libcommand-services-nautilus.so) and its core's test program (command-services-core-test), then runs
# the tests.
#
# Usage: build.sh <output folder> [--nautilus-headers <folder holding libnautilus-extension/>]
#
# Needs a C compiler, GLib/GIO development files (pkg-config glib-2.0 gio-2.0), and Nautilus's
# extension headers: the libnautilus-extension-dev package (pkg-config libnautilus-extension-4),
# or, where it cannot be installed, the headers of the installed Nautilus version from its source
# (libnautilus-extension/*.h; the generated nautilus-extension-enum-types.h, which the plug-in
# does not use, is stood in for), linked against the installed libnautilus-extension.so.4.
# Exit status: 0 built and tests passed, 1 a step failed, 2 bad arguments.

out="$1"
headers=""
if [ "$2" = "--nautilus-headers" ]; then
    headers="$3"
fi
if [ -z "$out" ] || { [ "$2" = "--nautilus-headers" ] && [ -z "$headers" ]; }; then
    printf 'Usage: %s <output folder> [--nautilus-headers <folder holding libnautilus-extension/>]\n' "$0" >&2
    exit 2
fi
here="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
/bin/mkdir -p "$out"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'cannot make %s\n' "$out" >&2
    exit 1
fi

glib_flags="$(/usr/bin/pkg-config --cflags --libs glib-2.0 gio-2.0 gobject-2.0 gmodule-2.0)"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'no GLib development files (pkg-config glib-2.0 gio-2.0)\n' >&2
    exit 1
fi
nautilus_flags="$(/usr/bin/pkg-config --cflags --libs libnautilus-extension-4 2>/dev/null)"
status=$?
if [ "$status" -ne 0 ] || [ -z "$nautilus_flags" ]; then
    if [ -z "$headers" ] || [ ! -f "$headers/libnautilus-extension/nautilus-extension.h" ]; then
        printf 'no libnautilus-extension-4 (install libnautilus-extension-dev, or give --nautilus-headers)\n' >&2
        exit 1
    fi
    library="$(/bin/ls /usr/lib/*/libnautilus-extension.so.4 /usr/lib64/libnautilus-extension.so.4 2>/dev/null | /usr/bin/head -n 1)"
    if [ -z "$library" ]; then
        printf 'no libnautilus-extension.so.4 installed (GNOME Files)\n' >&2
        exit 1
    fi
    # The generated enum types header: an empty stand-in (the plug-in uses no Nautilus enum type)
    stand_in="$out/include/libnautilus-extension"
    /bin/mkdir -p "$stand_in"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'cannot make %s\n' "$stand_in" >&2
        exit 1
    fi
    printf '#pragma once\n' > "$stand_in/nautilus-extension-enum-types.h"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'cannot write %s\n' "$stand_in/nautilus-extension-enum-types.h" >&2
        exit 1
    fi
    nautilus_flags="-I$headers -I$headers/libnautilus-extension -I$out/include $library"
fi

cc=/usr/bin/cc
warnings="-Wall -Wextra -Werror -Wno-unused-parameter"
# shellcheck disable=SC2086
"$cc" -std=gnu11 $warnings -O2 -fPIC -fvisibility=hidden -shared -o "$out/libcommand-services-nautilus.so" \
    "$here/command-services-nautilus.c" "$here/command-services-core.c" $nautilus_flags $glib_flags
status=$?
if [ "$status" -ne 0 ]; then
    printf 'the plug-in did not build\n' >&2
    exit 1
fi
# shellcheck disable=SC2086
"$cc" -std=gnu11 $warnings -O0 -g -o "$out/command-services-core-test" \
    "$here/command-services-core-test.c" "$here/command-services-core.c" $glib_flags
status=$?
if [ "$status" -ne 0 ]; then
    printf 'the core test did not build\n' >&2
    exit 1
fi
"$out/command-services-core-test"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'the core tests failed\n' >&2
    exit 1
fi
# The plug-in loaded as Nautilus loads it, asked for its menu with stand-in files
# shellcheck disable=SC2086
"$cc" -std=gnu11 $warnings -O0 -g -o "$out/command-services-nautilus-test" \
    "$here/command-services-nautilus-test.c" $nautilus_flags $glib_flags
status=$?
if [ "$status" -ne 0 ]; then
    printf 'the plug-in test did not build\n' >&2
    exit 1
fi
"$out/command-services-nautilus-test" "$out/libcommand-services-nautilus.so"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'the plug-in tests failed\n' >&2
    exit 1
fi
printf 'built %s\n' "$out/libcommand-services-nautilus.so"
exit 0
