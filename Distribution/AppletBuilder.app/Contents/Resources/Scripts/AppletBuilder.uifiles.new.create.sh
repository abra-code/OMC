#!/bin/bash
# AppletBuilder.uifiles.new.create - Create new UI file (ActionUI JSON)

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.tables.sh"

project_path=$(load_project_path)
resources_dir="$project_path/Contents/Resources"
lproj_dir="$resources_dir/Base.lproj"

name="${OMC_ACTIONUI_VIEW_841_VALUE}"

if [ -z "$name" ]; then
    set_value "$NEWUI_STATUS_ID" "Name is required"
    exit 1
fi

/bin/mkdir -p "$lproj_dir"

alert_tool="$OMC_OMC_SUPPORT_PATH/alert"
templates_dir="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Templates"

target_file="$lproj_dir/${name}.json"
if [ -f "$target_file" ]; then
    "$alert_tool" --level critical --title "AppletBuilder" \
        --ok "OK" \
        "A file named \"${name}.json\" already exists."
    set_value "$NEWUI_STATUS_ID" "File already exists"
    exit 1
fi

# Copy template from ActionUI Window applet
template_json="$templates_dir/ActionUI Window.applet/Contents/Resources/Base.lproj/Window.json"
if [ -f "$template_json" ]; then
    /bin/cp "$template_json" "$target_file"
else
    set_value "$NEWUI_STATUS_ID" "ActionUI template not found"
    exit 1
fi

# Refresh UI files table in the parent window
parent_uuid="$OMC_PARENT_DIALOG_GUID"

if [ -n "$parent_uuid" ]; then
    refresh_uifiles_table "$project_path" "$parent_uuid"
fi
