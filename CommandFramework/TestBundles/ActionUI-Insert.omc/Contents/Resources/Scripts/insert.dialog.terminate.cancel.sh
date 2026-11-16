#!/bin/sh
term_file="/tmp/OMC_test_insert_term_${OMC_ACTIONUI_WINDOW_UUID}"
term_tmp="${term_file}.tmp"
echo "TERM_COMPLETE=YES" > "$term_tmp"
echo "OMC_ACTIONUI_WINDOW_UUID=${OMC_ACTIONUI_WINDOW_UUID}" >> "$term_tmp"
mv "$term_tmp" "$term_file"
