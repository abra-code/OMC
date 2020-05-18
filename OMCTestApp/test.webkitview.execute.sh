#!/bin/sh

env | sort | grep "OMC_"

"$OMC_OMC_SUPPORT_PATH/alert" --title "Hello from HTML Button" --ok "OK" "This command has been triggered by JavaScript in WKWebView and executed in shell script"
