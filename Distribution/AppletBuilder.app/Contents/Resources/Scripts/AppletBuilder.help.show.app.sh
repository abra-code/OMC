#!/bin/bash
# AppletBuilder.help.show.services - Open help viewer with Services Reference

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.help.sh"

ensure_help_docs_converted

start_page="file://${HELP_HTML_DIR}/appletbuilder_user_guide.html"

"$pasteboard_tool" "HelpStartPage_${OMC_ACTIONUI_WINDOW_UUID}" set "$start_page"
"$next_cmd" "$cmd_guid" "AppletBuilder.help.dialog"
