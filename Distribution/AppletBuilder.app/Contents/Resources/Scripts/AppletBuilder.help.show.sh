#!/bin/bash
# AppletBuilder.help.show - Convert docs and open help viewer (UI Files context)

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.help.sh"

ensure_help_docs_converted

# Determine start page based on selected UI file type
selected_path=$(pb_get "$PB_UIFILES_SELECTED")

# A menu-bar document (MainMenu.json) has a top-level JSON array; a view document
# has an object root. Nib bundles are directories.
is_menubar="no"
if [ -f "$selected_path" ]; then
    if [ "$(/usr/bin/basename "$selected_path")" = "MainMenu.json" ]; then
        is_menubar="yes"
    else
        is_menubar=$("$python3" -c 'import json,sys; print("yes" if isinstance(json.load(open(sys.argv[1])),list) else "no")' "$selected_path" 2>/dev/null)
    fi
fi

if [ -d "$selected_path" ]; then
    start_page="file://${HELP_HTML_DIR}/Nib-Guide.html"
elif [ "$is_menubar" = "yes" ]; then
    start_page="file://${HELP_HTML_DIR}/ActionUI-MenuBar-JSON-Guide.html"
else
    start_page="file://${HELP_HTML_DIR}/ActionUI-JSON-Guide.html"
fi

"$pasteboard_tool" "HelpStartPage_${OMC_ACTIONUI_WINDOW_UUID}" set "$start_page"
"$next_cmd" "$cmd_guid" "AppletBuilder.help.dialog"
