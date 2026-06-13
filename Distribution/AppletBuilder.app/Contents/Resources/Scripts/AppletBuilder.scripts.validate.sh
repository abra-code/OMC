#!/bin/bash
# AppletBuilder.scripts.validate - Syntax-check the selected script by type

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.errors.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.validate.sh"

selected_path=$(pb_get "$PB_SCRIPTS_SELECTED")

if [ -z "$selected_path" ] || [ ! -f "$selected_path" ]; then
    set_value "$SCRIPTS_EDITED_LABEL_ID" "No file selected"
    exit 0
fi

filename=$(/usr/bin/basename "$selected_path")
ext=$(echo "${filename##*.}" | /usr/bin/tr '[:upper:]' '[:lower:]')

validate_script_file "$selected_path"
rc=$?

if [ "$rc" -eq 99 ]; then
    set_value "$SCRIPTS_EDITED_LABEL_ID" "No validator for .${ext} files"
    exit 0
fi

if [ "$rc" -eq 0 ]; then
    if [ -n "$SCRIPT_VALIDATE_WARNINGS" ]; then
        set_value "$SCRIPTS_EDITED_LABEL_ID" "⚠️ bash 4+ syntax"
        show_errors "Warnings in ${filename} — macOS ships bash 3.2, these constructs fail at runtime:

$SCRIPT_VALIDATE_WARNINGS"
    else
        set_value "$SCRIPTS_EDITED_LABEL_ID" "✅ Valid"
    fi
else
    set_value "$SCRIPTS_EDITED_LABEL_ID" "🛑 Syntax errors"
    show_errors "Syntax errors in ${filename}:

$SCRIPT_VALIDATE_OUTPUT"
fi
