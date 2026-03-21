#!/bin/bash
# Prettify JSON in the UI file editor

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

edited_content="${OMC_ACTIONUI_VIEW_702_VALUE}"
if [ -z "$edited_content" ]; then
    exit 0
fi

pretty=$(echo "$edited_content" | "$python3" -m json.tool 2>&1)
if [ "$?" -eq 0 ]; then
    set_value "$UI_DETAIL_ID" "$pretty"
    set_enabled "$UI_SAVE_BTN_ID" true
    set_value "$UI_EDITED_LABEL_ID" "🔴 Modified"
else
    set_value "$UI_EDITED_LABEL_ID" "Invalid JSON"
    show_errors "Cannot prettify — JSON syntax error:

$pretty"
fi
