#!/bin/bash
# AppletBuilder.new.browse.icon - Set custom icon path from file picker result

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

if [ -n "$OMC_DLG_CHOOSE_OBJECT_PATH" ]; then
    set_value "$NEW_ICON_ID" "$OMC_DLG_CHOOSE_OBJECT_PATH"
    "$dialog_tool" "$window_uuid" "$NEW_CUSTOM_ICON_ROW_ID" omc_set_property "hidden" "false"

    # Compile custom .icon to temp .icns for preview
    icon_base=$(/usr/bin/basename "${OMC_DLG_CHOOSE_OBJECT_PATH%.*}")
    temp_dir=$(/usr/bin/mktemp -d)
    /usr/bin/xcrun actool "$OMC_DLG_CHOOSE_OBJECT_PATH" \
        --compile "$temp_dir" \
        --app-icon "$icon_base" \
        --platform macosx \
        --target-device mac \
        --output-format human-readable-text \
        --minimum-deployment-target 14.6 \
        --output-partial-info-plist "$temp_dir/partial.plist" \
        > "$temp_dir/actool.log" 2>&1

    if [ -f "$temp_dir/${icon_base}.icns" ]; then
        set_value "$NEW_HEADER_IMAGE_ID" "$temp_dir/${icon_base}.icns"
    fi
fi
