#!/bin/bash
# AppletBuilder.general.name.changed - Auto-fill bundle ID only when name actually changed

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

name="${OMC_ACTIONUI_VIEW_302_VALUE}"

if [ -z "$name" ]; then
    exit 0
fi

# Only update bundle ID if the name actually changed from the saved value
project_path=$(load_project_path)
plist="$project_path/Contents/Info.plist"
old_name=$(plist_read "$plist" CFBundleName)

if [ "$name" != "$old_name" ]; then
    sanitized=$(echo "$name" | /usr/bin/tr '[:upper:]' '[:lower:]' | /usr/bin/tr ' ' '-' | /usr/bin/tr -cd 'a-z0-9-')
    prefix=$(get_bundle_id_prefix)
    bundle_id="${prefix}${sanitized}"
    set_value "$GEN_BUNDLE_ID_ID" "$bundle_id"
    set_value "$GEN_HEADER_NAME_ID" "$name"

    # Save name and bundle ID immediately
    plist_edit "$plist" set_keys CFBundleName "$name" CFBundleIdentifier "$bundle_id"
    set_value "$GEN_STATUS_ID" "Name updated"
fi
