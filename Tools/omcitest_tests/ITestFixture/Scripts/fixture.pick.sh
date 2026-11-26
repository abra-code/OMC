#!/bin/bash
# A folder panel that starts where the window's field (view 2) says: its DEFAULT_LOCATION names the
# field's value, which the engine must take from the window as it is when the command starts.
# Records the field and the chosen folder, one line per run.
if [ -n "$ITEST_WORK" ]; then
    printf 'pick:%s:%s\n' "${OMC_ACTIONUI_VIEW_2_VALUE}" "${OMC_DLG_CHOOSE_FOLDER_PATH%/}" >> "$ITEST_WORK/pick.txt"
fi
