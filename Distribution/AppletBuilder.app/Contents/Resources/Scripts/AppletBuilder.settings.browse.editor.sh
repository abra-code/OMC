#!/bin/bash
# AppletBuilder.settings.browse.editor - Handle editor selection from file picker

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

if [ -n "$OMC_DLG_CHOOSE_OBJECT_PATH" ]; then
    save_external_editor "$OMC_DLG_CHOOSE_OBJECT_PATH"
    editor_name=$(/usr/bin/basename "${OMC_DLG_CHOOSE_OBJECT_PATH%.app}")
    set_value "$SETTINGS_EDITOR_NAME_ID" "$editor_name"
    set_value "$SETTINGS_EDITOR_PATH_ID" "$OMC_DLG_CHOOSE_OBJECT_PATH"
fi
