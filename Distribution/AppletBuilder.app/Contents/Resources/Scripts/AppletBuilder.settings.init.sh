#!/bin/bash
# AppletBuilder.settings.init - Populate Settings dialog with current values

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

editor=$(get_external_editor)
editor_name=$(/usr/bin/basename "${editor%.app}")

set_value "$SETTINGS_EDITOR_NAME_ID" "$editor_name"
set_value "$SETTINGS_EDITOR_PATH_ID" "$editor"
