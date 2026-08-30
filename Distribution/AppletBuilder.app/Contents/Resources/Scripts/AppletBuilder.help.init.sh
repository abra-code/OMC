#!/bin/bash
# AppletBuilder.help.init - Load initial page into help viewer WebView

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.help.sh"

# Reset navigation tracking state
pb_set "$PB_HELP_NAV_COUNT" ""
pb_set "$PB_HELP_WENT_BACK" ""

# Read start page from parent dialog's pasteboard
start_page=""
if [ -n "$OMC_PARENT_DIALOG_GUID" ]; then
    start_page=$("$pasteboard_tool" "HelpStartPage_${OMC_PARENT_DIALOG_GUID}" get)
    "$pasteboard_tool" "HelpStartPage_${OMC_PARENT_DIALOG_GUID}" set ""
fi

if [ -z "$start_page" ]; then
    # Built from HELP_HTML_DIR rather than restated: the two paths must agree,
    # and a second spelling of it is a blank help window the day either moves.
    start_page="file://${HELP_HTML_DIR}/appletbuilder_user_guide.html"
fi

set_value "$HELP_WEBVIEW_ID" "$start_page"
