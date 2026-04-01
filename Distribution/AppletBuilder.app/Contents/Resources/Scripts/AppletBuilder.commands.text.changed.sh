#!/bin/bash
# Mark command detail as edited
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"
set_enabled "$CMD_SAVE_BTN_ID" true
set_value "$CMD_EDITED_LABEL_ID" "🔴 Modified"
pb_set "$PB_CMD_DIRTY" "1"
