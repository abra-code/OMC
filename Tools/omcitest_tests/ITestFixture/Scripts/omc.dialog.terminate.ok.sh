#!/bin/bash
# The end command a window with no END_OK_SUBCOMMAND_ID runs when it is OK'd (fixture.modal, and
# the modeless window, which names only an END_CANCEL_SUBCOMMAND_ID): its default name. Runs while
# the window still has its values.
if [ -n "$ITEST_WORK" ]; then
    printf 'terminate.ok:%s\n' "$OMC_ACTIONUI_VIEW_2_VALUE" >> "$ITEST_WORK/end.txt"
fi
