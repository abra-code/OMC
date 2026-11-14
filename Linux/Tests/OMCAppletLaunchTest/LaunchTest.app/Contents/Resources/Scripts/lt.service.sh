#!/bin/bash
# A file service (NSServices in Info.plist): run for the file manager with --omc-service
printf 'service:%s\n' "$OMC_OBJ_PATH" >> "$LAUNCHTEST_LOG"
