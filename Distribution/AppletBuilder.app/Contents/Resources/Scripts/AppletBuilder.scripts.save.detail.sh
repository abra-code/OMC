#!/bin/bash
# Save edited script content back to file

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

selected_path=$(pb_get "$PB_SCRIPTS_SELECTED")

if [ -z "$selected_path" ]; then
    set_value "$SCRIPTS_EDITED_LABEL_ID" "Error: no file selected"
    exit 1
fi

edited_content="${OMC_ACTIONUI_VIEW_602_VALUE}"

check_file_modified "$selected_path" "$PB_SCRIPTS_HASH"
case $? in
    1)  # Reload from Disk
        content=$(/bin/cat "$selected_path")
        set_value "$SCRIPTS_DETAIL_ID" "$content
"
        pb_set "$PB_SCRIPTS_HASH" "$(file_hash "$selected_path")"
        pb_set "$PB_SCRIPTS_DIRTY" ""
        set_enabled "$SCRIPTS_SAVE_BTN_ID" false
        set_value "$SCRIPTS_EDITED_LABEL_ID" "Reloaded from disk"
        exit 0
        ;;
    2)  # Cancel
        exit 0
        ;;
esac

# Save Anyway (0) or no conflict
printf "%s" "$edited_content" > "$selected_path"
if [ "$?" -eq 0 ]; then
    pb_set "$PB_SCRIPTS_HASH" "$(file_hash "$selected_path")"
    pb_set "$PB_SCRIPTS_DIRTY" ""
    set_enabled "$SCRIPTS_SAVE_BTN_ID" false
    set_value "$SCRIPTS_EDITED_LABEL_ID" "✅ Saved"
else
    set_value "$SCRIPTS_EDITED_LABEL_ID" "Error: failed to save"
fi
