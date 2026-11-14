#!/bin/bash
# Not a service: a service request naming it must be refused, so this line never appears
printf 'notservice:%s\n' "$OMC_OBJ_PATH" >> "$LAUNCHTEST_LOG"
