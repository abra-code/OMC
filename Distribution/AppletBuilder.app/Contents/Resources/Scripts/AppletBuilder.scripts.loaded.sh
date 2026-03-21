#!/bin/bash
# AppletBuilder.scripts.loaded - Populate Scripts table

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
scripts_dir="$project_path/Contents/Resources/Scripts"

if [ ! -d "$scripts_dir" ]; then
    set_value "$SCRIPTS_DETAIL_ID" "No Scripts directory found"
    exit 0
fi

refresh_scripts_table "$scripts_dir"
