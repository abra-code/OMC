#!/bin/bash
# Validate ActionUI JSON with the bundled Python verifier

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.errors.sh"

selected_path=$(pb_get "$PB_UIFILES_SELECTED")

if [ -z "$selected_path" ] || [ ! -f "$selected_path" ]; then
    set_value "$UI_EDITED_LABEL_ID" "No file selected"
    exit 0
fi

verifier="${OMC_APP_BUNDLE_PATH}/Contents/Library/actionui_verifier/validate_actionui.py"
if [ ! -f "$verifier" ]; then
    set_value "$UI_EDITED_LABEL_ID" "Verifier not found"
    exit 0
fi

verifier_output=$("$python3" "$verifier" "$selected_path" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    set_value "$UI_EDITED_LABEL_ID" "✅ Valid"
elif [ "$rc" -eq 2 ]; then
    set_value "$UI_EDITED_LABEL_ID" "⚠️ Warnings"
    show_errors "ActionUI validation warnings in $(/usr/bin/basename "$selected_path"):

$verifier_output"
else
    set_value "$UI_EDITED_LABEL_ID" "🛑 Validation errors"
    show_errors "ActionUI validation errors in $(/usr/bin/basename "$selected_path"):

$verifier_output"
fi
