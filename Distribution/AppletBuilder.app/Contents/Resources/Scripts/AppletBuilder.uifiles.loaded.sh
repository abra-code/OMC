#!/bin/bash
# AppletBuilder.uifiles.loaded - Populate UI Files table (nibs + ActionUI JSONs)

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
resources_dir="$project_path/Contents/Resources"
lproj_dir="$resources_dir/Base.lproj"

# Column 1 (visible): filename
# Column 2 (hidden): full path
buffer=""

# List .nib bundles
if [ -d "$lproj_dir" ]; then
    for nib in "$lproj_dir"/*.nib; do
        [ ! -d "$nib" ] && continue
        nib_name=$(/usr/bin/basename "$nib")
        buffer="${buffer}${nib_name}	${nib}
"
    done
fi

# List ActionUI JSON files (in Base.lproj)
if [ -d "$lproj_dir" ]; then
    for json in "$lproj_dir"/*.json; do
        [ ! -f "$json" ] && continue
        json_name=$(/usr/bin/basename "$json")
        buffer="${buffer}${json_name}	${json}
"
    done
fi

# Also check Resources root for JSON files
for json in "$resources_dir"/*.json; do
    [ ! -f "$json" ] && continue
    json_name=$(/usr/bin/basename "$json")
    buffer="${buffer}${json_name}	${json}
"
done

if [ -n "$buffer" ]; then
    printf "%s" "$buffer" | "$dialog_tool" "$window_uuid" "$UI_TABLE_ID" omc_table_set_rows_from_stdin
else
    set_value "$UI_DETAIL_ID" "No UI files found"
fi
