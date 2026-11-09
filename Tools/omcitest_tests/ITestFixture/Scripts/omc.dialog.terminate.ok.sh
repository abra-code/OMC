#!/bin/bash
# The end command a window with no END_OK_SUBCOMMAND_ID runs when it is OK'd (fixture.modal): its
# default name. Runs while the window still has its values.
if [ -n "$ITEST_WORK" ]; then
    printf 'terminate.ok:%s\n' "$OMC_ACTIONUI_VIEW_2_VALUE" >> "$ITEST_WORK/modal.end.txt"
fi
