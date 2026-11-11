#!/bin/sh
# A blocking window's INIT_SUBCOMMAND_ID: logs; the window stays open (its modal run goes on)
printf 'modal.init\n' >> "$LAUNCHTEST_LOG"
