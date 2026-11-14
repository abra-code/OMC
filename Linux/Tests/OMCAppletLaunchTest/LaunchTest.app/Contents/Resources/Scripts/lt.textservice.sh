#!/bin/bash
# A service for text only (NSSendTypes): a file service request naming it must be refused
printf 'textservice:%s\n' "$OMC_OBJ_PATH" >> "$LAUNCHTEST_LOG"
