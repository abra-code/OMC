#!/bin/bash
# The end command a window with no END_CANCEL_SUBCOMMAND_ID runs when it is canceled
# (fixture.modal): its default name. Runs while the window still has its values.
if [ -n "$ITEST_WORK" ]; then
    printf 'terminate.cancel:%s\n' "$OMC_ACTIONUI_VIEW_2_VALUE" >> "$ITEST_WORK/modal.end.txt"
fi
