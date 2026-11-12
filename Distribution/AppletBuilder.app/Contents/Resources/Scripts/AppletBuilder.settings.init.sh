#!/bin/bash
# AppletBuilder.settings.init - Populate Settings dialog with current values

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.prefs.sh"

editor=$(get_external_editor)
editor_name=$(external_editor_name "$editor")

set_value "$SETTINGS_EDITOR_NAME_ID" "$editor_name"
set_value "$SETTINGS_EDITOR_PATH_ID" "$editor"
