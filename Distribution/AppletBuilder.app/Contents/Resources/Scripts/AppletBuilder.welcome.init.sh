#!/bin/bash
# AppletBuilder.welcome.init - Fill the Welcome window: AppletBuilder's icon, name and version, and
# the recent applets (icon, name, folder; double-click opens one). One Welcome window at a time: an
# earlier one closes. A project window closes it (project.init), so on Linux the app always has a
# window while the user goes from here to an applet.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.prefs.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.plist.sh"

earlier_welcome="$(pb_get "$PB_WELCOME_WINDOW")"
if [ -n "$earlier_welcome" ] && [ "$earlier_welcome" != "$window_uuid" ]; then
    ab_welcome_close
fi
pb_set "$PB_WELCOME_WINDOW" "$window_uuid"

own_plist="${OMC_APP_BUNDLE_PATH}/Contents/Info.plist"
own_icon="$(applet_icon_preview "$OMC_APP_BUNDLE_PATH" "$(plist_read "$own_plist" CFBundleIconFile)")"
if [ -n "$own_icon" ]; then
    set_value "$WELCOME_ICON_ID" "$own_icon"
fi
own_name="$(plist_read "$own_plist" CFBundleName)"
set_value "$WELCOME_NAME_ID" "${own_name:-AppletBuilder}"
own_version="$(plist_read "$own_plist" CFBundleShortVersionString)"
# AppletBuilder's Info.plist has only CFBundleVersion (as the General tab reads an applet's)
if [ -z "$own_version" ]; then
    own_version="$(plist_read "$own_plist" CFBundleVersion)"
fi
if [ -n "$own_version" ]; then
    set_value "$WELCOME_VERSION_ID" "Version ${own_version}"
fi

# The icon shown for an applet that has none of its own: the template applets' icon
icons_dir="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Icons"
default_icon="${icons_dir}/CommandApplet.icns"
if ! ab_on_macos; then
    default_icon="${icons_dir}/CommandApplet.svg"
fi

# Rows: path (hidden), icon, name, folder (~ for the home folder). Tabs and line breaks would
# split a row, so none are kept in a name.
rows=""
count=0
while IFS= read -r applet; do
    if [ -z "$applet" ] || [ ! -f "$applet/Contents/Info.plist" ]; then
        continue
    fi
    # Captured first: the substitution drops the trailing newline, so tr leaves no trailing space
    name="$(plist_read "$applet/Contents/Info.plist" CFBundleName)"
    name="$(printf '%s' "$name" | /usr/bin/tr '\t\n' '  ')"
    if [ -z "$name" ]; then
        name="$(/usr/bin/basename "$applet" .app)"
    fi
    icon="$(applet_icon_preview "$applet" "$(plist_read "$applet/Contents/Info.plist" CFBundleIconFile)")"
    if [ -z "$icon" ]; then
        icon="$default_icon"
    fi
    folder="$(/usr/bin/dirname "$applet")"
    case "$folder" in
        "$HOME") folder="~" ;;
        "$HOME"/*) folder="~${folder#"$HOME"}" ;;
    esac
    rows="${rows}${applet}	${icon}	${name}	${folder}
"
    count=$((count + 1))
done <<EOF
$(recent_applets)
EOF

printf '%s' "$rows" | "$dialog_tool" "$window_uuid" "$WELCOME_RECENT_LIST_ID" omc_table_set_rows_from_stdin
if [ "$count" -eq 0 ]; then
    set_value "$WELCOME_NOTE_ID" "No recent applets yet: the ones you open or make are listed here."
    "$dialog_tool" "$window_uuid" "$WELCOME_NOTE_ID" omc_set_property "hidden" "false"
fi
