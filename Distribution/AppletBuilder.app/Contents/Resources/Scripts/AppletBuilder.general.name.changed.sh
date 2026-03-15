#!/bin/bash
# AppletBuilder.general.name.changed - Auto-fill bundle ID and update header name

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

name="${OMC_ACTIONUI_VIEW_302_VALUE}"

if [ -n "$name" ]; then
    sanitized=$(echo "$name" | /usr/bin/tr '[:upper:]' '[:lower:]' | /usr/bin/tr ' ' '-' | /usr/bin/tr -cd 'a-z0-9-')
    prefix=$(get_bundle_id_prefix)
    bundle_id="${prefix}${sanitized}"
    set_value "$GEN_BUNDLE_ID_ID" "$bundle_id"
    set_value "$GEN_HEADER_NAME_ID" "$name"
fi
