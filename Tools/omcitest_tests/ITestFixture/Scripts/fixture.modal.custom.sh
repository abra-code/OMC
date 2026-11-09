#!/bin/bash
# Runs after its blocking window (ModalCustom) was OK'd through its own END_OK_SUBCOMMAND_ID, with
# the field the window had.
if [ -n "$ITEST_WORK" ]; then
    printf 'main:%s\n' "$OMC_ACTIONUI_VIEW_2_VALUE" >> "$ITEST_WORK/custom.txt"
fi
