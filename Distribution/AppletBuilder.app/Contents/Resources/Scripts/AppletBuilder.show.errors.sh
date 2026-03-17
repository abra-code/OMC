#!/bin/bash
# Display error details in output window, read from private pasteboard

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

errors=$("$pasteboard_tool" "$APPLET_BUILDER_ERRORS_PB" get 2>/dev/null)
"$pasteboard_tool" "$APPLET_BUILDER_ERRORS_PB" set ""

if [ -n "$errors" ]; then
    echo "$errors"
else
    echo "No error details available"
fi
