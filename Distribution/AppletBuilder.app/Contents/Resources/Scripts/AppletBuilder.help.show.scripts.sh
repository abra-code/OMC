#!/bin/bash
# AppletBuilder.help.show.scripts - Open help viewer with appropriate Scripting Guide

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

ensure_help_docs_converted

# Determine which guide to show based on selected script type
start_page="file://${HELP_HTML_DIR}/omc_scripting_guide.html"

selected_path=$(pb_get "$PB_SCRIPTS_SELECTED")
case "$selected_path" in
    *.py)
        start_page="file://${HELP_HTML_DIR}/omc_python_scripting_guide.html"
        ;;
esac

"$pasteboard_tool" "HelpStartPage_${OMC_ACTIONUI_WINDOW_UUID}" set "$start_page"
"$next_cmd" "$cmd_guid" "AppletBuilder.help.dialog"
