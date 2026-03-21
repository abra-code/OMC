#!/bin/bash
# Mark UI file detail as edited
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"
set_enabled "$UI_SAVE_BTN_ID" true
set_value "$UI_EDITED_LABEL_ID" "🔴 Modified"
