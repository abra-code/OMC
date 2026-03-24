#!/bin/bash
# Display reference content in output window, read from private pasteboard

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

APPLET_BUILDER_REFERENCE_PB="APPLET_BUILDER_REFERENCE"

content=$("$pasteboard_tool" "$APPLET_BUILDER_REFERENCE_PB" get 2>/dev/null)
"$pasteboard_tool" "$APPLET_BUILDER_REFERENCE_PB" set ""

if [ -n "$content" ]; then
    echo "$content"
fi
