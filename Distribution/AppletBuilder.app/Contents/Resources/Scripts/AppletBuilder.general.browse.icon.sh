#!/bin/bash
# AppletBuilder.general.browse.icon - Install selected .icon into the applet

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

icon_source="$OMC_DLG_CHOOSE_OBJECT_PATH"
if [ -z "$icon_source" ] || [ ! -e "$icon_source" ]; then
    exit 0
fi

project_path=$(load_project_path)
if [ -z "$project_path" ] || [ ! -d "$project_path" ]; then
    set_status "$GEN_STATUS_ID" "No project loaded"
    exit 1
fi

set_status "$GEN_STATUS_ID" "Installing icon..."

applet_install_icon "$icon_source" "$project_path"
if [ $? -eq 0 ]; then
    # Remove old icon files that don't match the new one
    icon_base=$(/usr/bin/basename "${icon_source%.*}")
    for old_icns in "$project_path/Contents/Resources/"*.icns; do
        [ ! -f "$old_icns" ] && continue
        old_base=$(/usr/bin/basename "${old_icns%.icns}")
        if [ "$old_base" != "$icon_base" ]; then
            /bin/rm -f "$old_icns"
        fi
    done

    # Update header icon preview
    icns_path="$project_path/Contents/Resources/${icon_base}.icns"
    if [ -f "$icns_path" ]; then
        set_value "$GEN_ICON_IMAGE_ID" "$icns_path"
    fi

    applet_finalize "$project_path"
    set_status "$GEN_STATUS_ID" "Icon updated"
else
    set_status "$GEN_STATUS_ID" "Failed to compile icon"
fi
