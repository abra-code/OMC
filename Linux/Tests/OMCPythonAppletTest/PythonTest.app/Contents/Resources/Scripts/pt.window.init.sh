#!/bin/sh
# The window's INIT_SUBCOMMAND_ID: once this returns, the embedded python3 (first on PATH) works
# the open window through omc.py: it reads field 2 over the ActionUI remote bridge, writes it back
# changed, and closes the window with OK
printf 'window.init\n' >> "$PYTHONTEST_LOG"
python3 "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/pt_window_worker.py" > /dev/null 2>&1 &
