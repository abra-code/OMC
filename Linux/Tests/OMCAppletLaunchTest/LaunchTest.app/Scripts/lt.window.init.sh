#!/bin/sh
# The window's INIT_SUBCOMMAND_ID: logs the window, then (after this returns) sets field 2 and
# closes the window with OK through omc_dialog_control, as a handler would
printf 'window.init:%s\n' "$OMC_ACTIONUI_WINDOW_UUID" >> "$LAUNCHTEST_LOG"
(
    /bin/sleep 1
    "$OMC_OMC_SUPPORT_PATH/omc_dialog_control" "$OMC_ACTIONUI_WINDOW_UUID" 2 "set by omc_dialog_control"
    printf 'window.set:%s\n' "$?" >> "$LAUNCHTEST_LOG"
    /bin/sleep 0.5
    "$OMC_OMC_SUPPORT_PATH/omc_dialog_control" "$OMC_ACTIONUI_WINDOW_UUID" omc_window omc_terminate_ok
    printf 'window.terminate:%s\n' "$?" >> "$LAUNCHTEST_LOG"
) > /dev/null 2>&1 &
