#!/bin/bash
# AppletBuilder.uifiles.loaded - Populate UI Files table (nibs + ActionUI JSONs)

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
resources_dir="$project_path/Contents/Resources"
lproj_dir="$resources_dir/Base.lproj"

refresh_uifiles_table "$project_path"
