#!/bin/bash
# AppletBuilder.general.loaded - Populate General tab when its LoadableView finishes loading

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)

# If project.init hasn't saved the path yet (race), read from the pending file
# and save it ourselves so subsequent tabs find it
if [ -z "$project_path" ]; then
    pending="/tmp/appletbuilder_pending_project"
    if [ -f "$pending" ]; then
        project_path=$(cat "$pending")
        /bin/rm -f "$pending"
        if [ -n "$project_path" ] && [ -d "$project_path" ]; then
            save_project_path "$project_path"
        fi
    fi
fi

if [ -n "$project_path" ] && [ -f "$project_path/Contents/Info.plist" ]; then
    plist="$project_path/Contents/Info.plist"

    app_name=$(plist_read "$plist" CFBundleName)
    set_value "$GEN_NAME_ID" "$app_name"
    set_value "$GEN_HEADER_NAME_ID" "$app_name"
    set_value "$GEN_BUNDLE_ID_ID" "$(plist_read "$plist" CFBundleIdentifier)"
    set_value "$GEN_VERSION_ID" "$(plist_read "$plist" CFBundleVersion)"

    # Set header icon
    icon_name=$(plist_read "$plist" CFBundleIconFile)
    icns_path="$project_path/Contents/Resources/${icon_name}.icns"
    if [ -f "$icns_path" ]; then
        set_value "$GEN_ICON_IMAGE_ID" "$icns_path"
    fi
fi
