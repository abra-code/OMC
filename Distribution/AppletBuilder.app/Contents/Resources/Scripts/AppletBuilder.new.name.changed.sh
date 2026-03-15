#!/bin/bash
# AppletBuilder.new.name.changed - Auto-fill bundle ID and update header name

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

name="${OMC_ACTIONUI_VIEW_203_VALUE}"

if [ -n "$name" ]; then
    sanitized=$(echo "$name" | /usr/bin/tr '[:upper:]' '[:lower:]' | /usr/bin/tr ' ' '-' | /usr/bin/tr -cd 'a-z0-9-')
    prefix=$(get_bundle_id_prefix)
    bundle_id="${prefix}${sanitized}"
    set_value "$NEW_BUNDLE_ID_ID" "$bundle_id"
    set_value "$NEW_HEADER_NAME_ID" "$name"
    set_enabled "$NEW_CREATE_BTN_ID" 1
else
    set_value "$NEW_HEADER_NAME_ID" "New Applet"
    set_enabled "$NEW_CREATE_BTN_ID" 0
fi
