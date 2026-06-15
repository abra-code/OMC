#!/bin/bash
# AppletBuilder.new.create - GUI front end for creating an applet from a template.
#
# The create pipeline lives in lib.create.sh (applet_create_from_template), shared
# with the agent CLI. This handler reads the New Applet form, routes progress/errors
# to the status field, runs the pipeline, then opens the new applet for editing.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.create.sh"

# ── Reporters → the New Applet status field (override stderr defaults) ──
ab_log()    { set_status "$NEW_STATUS_ID" "$1"; }
ab_report() { set_status "$NEW_STATUS_ID" "$1"; }

# ── Read form values ──
template_tag="${OMC_ACTIONUI_VIEW_201_VALUE}"
template_path="${OMC_ACTIONUI_VIEW_202_VALUE}"
templates_dir="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Templates"
icons_dir="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Icons"

# Resolve template path from tag if not cloning
if [ "$template_tag" != "__clone__" ] && [ -z "$template_path" ]; then
    template_path="${templates_dir}/${template_tag}.applet"
fi

applet_name="${OMC_ACTIONUI_VIEW_203_VALUE}"
bundle_id="${OMC_ACTIONUI_VIEW_204_VALUE}"
custom_icon_path="${OMC_ACTIONUI_VIEW_206_VALUE}"
requires_python="${OMC_ACTIONUI_VIEW_208_VALUE}"
icon_tag="${OMC_ACTIONUI_VIEW_209_VALUE}"
dest_folder="${OMC_DLG_CHOOSE_FOLDER_PATH}"

# Resolve icon path
icon_path=""
if [ "$icon_tag" = "__custom__" ]; then
    icon_path="$custom_icon_path"
elif [ -n "$icon_tag" ]; then
    icon_path="${icons_dir}/${icon_tag}.icon"
fi

is_clone=""
[ "$template_tag" = "__clone__" ] && is_clone="1"

# ── Create ──
applet_create_from_template \
    "$template_path" "$applet_name" "$dest_folder" \
    "$bundle_id" "$icon_path" "$requires_python" "$is_clone" || exit 1

# ── Open the new applet for editing ──
new_app_path="${dest_folder}/${applet_name}.app"
"$dialog_tool" "$window_uuid" omc_window omc_terminate_cancel
/usr/bin/open -a "$OMC_APP_BUNDLE_PATH" "$new_app_path"
