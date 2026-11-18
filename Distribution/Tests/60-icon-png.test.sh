#!/bin/sh
# Tests/60-icon-png.test.sh - the PNG icon a Linux applet carries.
#
# The build writes Resources/<icon>.png from the applet's .icns with icon_png.py.
# Linux icon themes stop at 512 pixels (hicolor's 512x512 folder), so the PNG is
# the largest image of at most 512 pixels: a 1024-pixel one fits no folder there
# and the desktop entry has to name the file by its path. An .icns with nothing
# that small gives its smallest image above 512.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.appletbuilder.sh"

ab_python="$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3"
icon_png="$AB_SCRIPTS/icon_png.py"
make_icns="$OMCTEST_TESTS/helpers/make_icns.py"
work="$OMCTEST_WORK/iconpng"
/bin/mkdir -p "$work"

# Writes an .icns with the given sizes, runs icon_png.py on it, and prints what
# it printed and which entry it copied ("512x512 size 512")
icon_from() {
    _icon_name="$1"
    shift
    PYTHONDONTWRITEBYTECODE=1 "$ab_python" -B "$make_icns" "$work/$_icon_name.icns" "$@"
    _icon_said="$(PYTHONDONTWRITEBYTECODE=1 "$ab_python" -B "$icon_png" "$work/$_icon_name.icns" "$work/$_icon_name.png")"
    _icon_copied="$(/usr/bin/grep -a -o 'size [0-9]*' "$work/$_icon_name.png")"
    printf '%s %s\n' "$_icon_said" "$_icon_copied"
}

section "1. a macOS icon's 1024 and 512 images: the 512 one"
check "512 from 1024, 512, 256 and 32" "512x512 size 512" "$(icon_from full 32 1024 256 512)"

section "2. nothing above 512: the largest, as before"
check "256 from 256, 128 and 32" "256x256 size 256" "$(icon_from small 256 32 128)"

section "3. only images above 512: the smallest of them"
check "1024 from 2048 and 1024" "1024x1024 size 1024" "$(icon_from large 2048 1024)"

section "4. no PNG image at all: refused, nothing written"
printf 'icns\000\000\000\010' > "$work/empty.icns"
PYTHONDONTWRITEBYTECODE=1 "$ab_python" -B "$icon_png" "$work/empty.icns" "$work/empty.png" > /dev/null 2>&1
empty_status=$?
check "exit status 1" "1" "$empty_status"
check "no PNG written" "no" "$([ -e "$work/empty.png" ] && echo yes || echo no)"

omctest_end
