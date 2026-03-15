#!/bin/bash
# AppletBuilder.new.python.changed - Switch default icon when Python toggled

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

python_on="${OMC_ACTIONUI_VIEW_208_VALUE}"
icon_selected="${OMC_ACTIONUI_VIEW_209_VALUE}"
icons_dir="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Icons"

# Only switch icon if a bundled icon is selected (not custom)
if [ "$icon_selected" != "__custom__" ]; then
    if [ "$python_on" = "1" ] || [ "$python_on" = "true" ]; then
        icon_name="OMCPythonApplet"
    else
        icon_name="OMCApplet"
    fi
    set_value "$NEW_ICON_PICKER_ID" "$icon_name"

    # Update header icon
    icns_path="${icons_dir}/${icon_name}.icns"
    if [ -f "$icns_path" ]; then
        set_value "$NEW_HEADER_IMAGE_ID" "$icns_path"
    fi
fi
