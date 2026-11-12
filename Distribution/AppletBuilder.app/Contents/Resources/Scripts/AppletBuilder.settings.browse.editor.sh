#!/bin/bash
# AppletBuilder.settings.browse.editor - Handle editor selection from file picker

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.prefs.sh"

if [ -n "$OMC_DLG_CHOOSE_OBJECT_PATH" ]; then
    save_external_editor "$OMC_DLG_CHOOSE_OBJECT_PATH"
    editor_name=$(external_editor_name "$OMC_DLG_CHOOSE_OBJECT_PATH")
    set_value "$SETTINGS_EDITOR_NAME_ID" "$editor_name"
    set_value "$SETTINGS_EDITOR_PATH_ID" "$OMC_DLG_CHOOSE_OBJECT_PATH"
fi
