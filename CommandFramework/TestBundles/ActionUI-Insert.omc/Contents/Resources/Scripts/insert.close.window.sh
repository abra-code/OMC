#!/bin/sh
WINDOW_UUID="${OMC_OBJ_TEXT}"
if [ -n "${WINDOW_UUID}" ]; then
    "$OMC_OMC_SUPPORT_PATH/omc_dialog_control" "$WINDOW_UUID" omc_window omc_terminate_cancel
fi
