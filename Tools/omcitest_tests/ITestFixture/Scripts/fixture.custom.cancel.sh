#!/bin/bash
# fixture.modal.custom's END_CANCEL_SUBCOMMAND_ID: the action that cancels its window, and the end
# command that runs as the window closes, while it still has its values.
if [ -n "$ITEST_WORK" ]; then
    printf 'cancel:%s\n' "$OMC_ACTIONUI_VIEW_2_VALUE" >> "$ITEST_WORK/custom.end.txt"
fi
