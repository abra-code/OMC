#!/bin/bash
# The applets' settings tool from the engine's Support folder: a value written, then read back,
# in the settings folder the test gives (XDG_CONFIG_HOME)
defaults="$OMC_OMC_SUPPORT_PATH/defaults"
"$defaults" write com.abracode.launchtest Greeting "hello there"
written=$?
value="$("$defaults" read com.abracode.launchtest Greeting)"
printf 'defaults:%s:%s\n' "$written" "$value" >> "$LAUNCHTEST_LOG"
