#!/bin/bash
# Mark script detail as edited
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"
set_enabled "$SCRIPTS_SAVE_BTN_ID" true
set_value "$SCRIPTS_EDITED_LABEL_ID" "🔴 Modified"
