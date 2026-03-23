#!/bin/bash
# AppletBuilder.help.show - Convert docs and open help viewer (UI Files context)

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

ensure_help_docs_converted

# Determine start page based on selected UI file type
selected_path=$(pb_get "$PB_UIFILES_SELECTED")

if [ -d "$selected_path" ]; then
    start_page="file://${HELP_HTML_DIR}/Nib-Guide.html"
else
    start_page="file://${HELP_HTML_DIR}/ActionUI-JSON-Guide.html"
fi

"$pasteboard_tool" "HelpStartPage_${OMC_ACTIONUI_WINDOW_UUID}" set "$start_page"
"$next_cmd" "$cmd_guid" "AppletBuilder.help.dialog"
