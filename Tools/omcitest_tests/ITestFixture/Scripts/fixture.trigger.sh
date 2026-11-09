#!/bin/bash
# The window's Trigger button: records, one line per run, the trigger variables the engine handed
# this handler - the element that fired, its part, and the action's context - with "<unset>" for a
# variable that is not in the environment at all.
if [ -n "$ITEST_WORK" ]; then
    printf '%s|%s|%s\n' "${OMC_ACTIONUI_TRIGGER_VIEW_ID-<unset>}" "${OMC_ACTIONUI_TRIGGER_VIEW_PART_ID-<unset>}" "${OMC_ACTIONUI_TRIGGER_CONTEXT-<unset>}" >> "$ITEST_WORK/trigger.txt"
fi
