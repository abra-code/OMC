#!/bin/bash
# Uses NIB_DIALOG, which 6.0 refuses: never runs.
if [ -n "$ITEST_WORK" ]; then printf 'ran\n' >> "$ITEST_WORK/nib.txt"; fi
