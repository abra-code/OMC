#!/bin/bash
# AppletBuilder.help.show.commands - Open help viewer with Command Reference

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

ensure_help_docs_converted

start_page="file://${HELP_HTML_DIR}/omc_command_reference.html"

"$pasteboard_tool" "HelpStartPage_${OMC_ACTIONUI_WINDOW_UUID}" set "$start_page"
"$next_cmd" "$cmd_guid" "AppletBuilder.help.dialog"
