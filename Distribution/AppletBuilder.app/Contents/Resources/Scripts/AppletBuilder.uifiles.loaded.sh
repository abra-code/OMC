#!/bin/bash
# AppletBuilder.uifiles.loaded - Populate UI Files table (nibs + ActionUI JSONs)

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
resources_dir="$project_path/Contents/Resources"
lproj_dir="$resources_dir/Base.lproj"

refresh_uifiles_table "$project_path"

# Populate the template picker from ElementTemplates.json
templates_json="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Base.lproj/ElementTemplates.json"
if [ -f "$templates_json" ]; then
    options=$(/bin/cat "$templates_json" | /usr/bin/tr -d '\n')
    "$dialog_tool" "$window_uuid" "$UI_TEMPLATE_PICKER_ID" omc_set_property options "$options"
fi
