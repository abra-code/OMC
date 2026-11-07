#!/bin/bash
"$OMC_OMC_SUPPORT_PATH/pasteboard" fixture_handoff put "handoff"
echo "handoff:$("$OMC_OMC_SUPPORT_PATH/pasteboard" fixture_handoff get)"
