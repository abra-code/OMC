#!/bin/bash
# Validate ActionUI JSON: check JSON syntax, then run ActionUIVerifier

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

state_dir=$(get_state_dir)
selected_path=$(cat "$state_dir/uifiles_selected_path" 2>/dev/null)

if [ -z "$selected_path" ] || [ ! -f "$selected_path" ]; then
    set_value "$UI_EDITED_LABEL_ID" "No file selected"
    exit 0
fi

# Step 1: JSON syntax check
json_error=$("$python3" -m json.tool "$selected_path" 2>&1 >/dev/null)
if [ "$?" -ne 0 ]; then
    set_value "$UI_EDITED_LABEL_ID" "Invalid JSON"
    show_errors "JSON syntax error in $(/usr/bin/basename "$selected_path"):

$json_error"
    exit 0
fi

# Step 2: ActionUI-specific validation
verifier="${OMC_APP_BUNDLE_PATH}/Contents/Helpers/ActionUIVerifier"
if [ -x "$verifier" ]; then
    verifier_result=$("$verifier" "$selected_path" 2>&1)
    if [ "$?" -eq 0 ]; then
        set_value "$UI_EDITED_LABEL_ID" "Valid"
    else
        set_value "$UI_EDITED_LABEL_ID" "Validation errors"
        show_errors "ActionUI validation errors in $(/usr/bin/basename "$selected_path"):

$verifier_result"
    fi
else
    set_value "$UI_EDITED_LABEL_ID" "Valid JSON (ActionUIVerifier not found)"
fi
