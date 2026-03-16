#!/bin/bash
# AppletBuilder.scripts.loaded - Populate Scripts table

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
scripts_dir="$project_path/Contents/Resources/Scripts"

if [ ! -d "$scripts_dir" ]; then
    set_value "$SCRIPTS_DETAIL_ID" "No Scripts directory found"
    exit 0
fi

# Column 1 (visible): script filename
# Column 2 (hidden): full path
buffer=""
for script in "$scripts_dir"/*; do
    [ ! -f "$script" ] && continue
    script_name=$(/usr/bin/basename "$script")
    buffer="${buffer}${script_name}	${script}
"
done

if [ -n "$buffer" ]; then
    printf "%s" "$buffer" | "$dialog_tool" "$window_uuid" "$SCRIPTS_TABLE_ID" omc_table_set_rows_from_stdin
fi
