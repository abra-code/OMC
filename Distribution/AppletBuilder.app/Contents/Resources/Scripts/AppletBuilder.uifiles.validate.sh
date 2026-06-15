#!/bin/bash
# Validate the selected ActionUI JSON file and present the result. The validation
# (bundled actionui_verifier) lives in validate_actionui_file (lib.validate.sh),
# shared with the build pipeline and the agent CLI.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.errors.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.validate.sh"

selected_path=$(pb_get "$PB_UIFILES_SELECTED")

if [ -z "$selected_path" ] || [ ! -f "$selected_path" ]; then
    set_value "$UI_EDITED_LABEL_ID" "No file selected"
    exit 0
fi

validate_actionui_file "$selected_path"
rc=$?

case "$rc" in
    0)
        set_value "$UI_EDITED_LABEL_ID" "✅ Valid"
        ;;
    2)
        set_value "$UI_EDITED_LABEL_ID" "⚠️ Warnings"
        show_errors "ActionUI validation warnings in $(/usr/bin/basename "$selected_path"):

$ACTIONUI_VALIDATE_OUTPUT"
        ;;
    99)
        set_value "$UI_EDITED_LABEL_ID" "Verifier not found"
        ;;
    *)
        set_value "$UI_EDITED_LABEL_ID" "🛑 Validation errors"
        show_errors "ActionUI validation errors in $(/usr/bin/basename "$selected_path"):

$ACTIONUI_VALIDATE_OUTPUT"
        ;;
esac
