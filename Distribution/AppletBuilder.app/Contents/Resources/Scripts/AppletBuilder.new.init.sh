#!/bin/bash
# AppletBuilder.new.init - Initialize the New Applet dialog, populate pickers

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

# set_window_title "New Applet"

templates_dir="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Templates"
icons_dir="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Icons"

# ── Populate template picker ──

options_json="["
first=1
for applet in "$templates_dir"/*.applet; do
    [ ! -d "$applet" ] && continue
    local_name=$(/usr/bin/basename "${applet%.applet}")
    if [ $first -eq 1 ]; then
        first=0
    else
        options_json="${options_json},"
    fi
    options_json="${options_json}{\"title\": \"${local_name}\", \"tag\": \"${local_name}\"}"
done

# Add separator and Clone option
if [ $first -eq 0 ]; then
    options_json="${options_json},{\"divider\": true}"
fi
options_json="${options_json},{\"title\": \"Clone Existing App\u2026\", \"tag\": \"__clone__\"}]"

"$dialog_tool" "$window_uuid" "$NEW_TYPE_PICKER_ID" omc_set_property "options" "$options_json"

# ── Populate icon picker ──

icon_json="["
first=1
for icon in "$icons_dir"/*.icon; do
    [ ! -d "$icon" ] && continue
    icon_name=$(/usr/bin/basename "${icon%.icon}")
    if [ $first -eq 1 ]; then
        first=0
    else
        icon_json="${icon_json},"
    fi
    icon_json="${icon_json}{\"title\": \"${icon_name}\", \"tag\": \"${icon_name}\"}"
done

# Add separator and Custom option
if [ $first -eq 0 ]; then
    icon_json="${icon_json},{\"divider\": true}"
fi
icon_json="${icon_json},{\"title\": \"Custom\u2026\", \"tag\": \"__custom__\"}]"

"$dialog_tool" "$window_uuid" "$NEW_ICON_PICKER_ID" omc_set_property "options" "$icon_json"

# ── Set default header icon ──

default_icns="${icons_dir}/OMCApplet.icns"
if [ -f "$default_icns" ]; then
    set_value "$NEW_HEADER_IMAGE_ID" "$default_icns"
fi
