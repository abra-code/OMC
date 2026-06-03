#!/bin/bash
# lib.errors.sh - Error / reference output windows for AppletBuilder
#
# Sources lib.common.sh for: pasteboard_tool, next_cmd, cmd_guid

[ -n "$__LIB_ERRORS_SH" ] && return 0
__LIB_ERRORS_SH=1

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.common.sh"

APPLET_BUILDER_ERRORS_PB="APPLET_BUILDER_ERRORS"

# Show error details in an output window via private pasteboard
show_errors() {
    local error_text="$1"
    "$pasteboard_tool" "$APPLET_BUILDER_ERRORS_PB" set "$error_text"
    "$next_cmd" "$cmd_guid" "AppletBuilder.show.errors"
}

APPLET_BUILDER_REFERENCE_PB="APPLET_BUILDER_REFERENCE"

# Show reference content in an output window via private pasteboard
show_reference() {
    local content="$1"
    "$pasteboard_tool" "$APPLET_BUILDER_REFERENCE_PB" set "$content"
    "$next_cmd" "$cmd_guid" "AppletBuilder.show.reference"
}
