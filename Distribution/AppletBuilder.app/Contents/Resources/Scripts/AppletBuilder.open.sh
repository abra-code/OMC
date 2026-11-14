#!/bin/bash
# AppletBuilder.open - Open (File menu, Welcome window's Open button): the chosen applet opens in a
# project window. The engine runs this only when the folder chooser was not canceled.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.common.sh"

applet="${OMC_DLG_CHOOSE_FOLDER_PATH%/}"
if [ -z "$applet" ]; then
    exit 0
fi
case "$applet" in
    *.app) ;;
    *) applet="" ;;
esac
if [ -z "$applet" ] || [ ! -f "$applet/Contents/Info.plist" ]; then
    "$OMC_OMC_SUPPORT_PATH/alert" --level critical --title "AppletBuilder" --ok "OK" \
        "Not an applet: ${OMC_DLG_CHOOSE_FOLDER_PATH}. Choose a folder whose name ends in .app." > /dev/null 2>&1
    exit 1
fi
ab_open_project "$applet"
