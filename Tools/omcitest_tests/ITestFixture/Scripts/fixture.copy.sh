#!/bin/bash
printf 'copied:%s' "${OMC_OBJ_TEXT}" | "$OMC_OMC_SUPPORT_PATH/pasteboard" general put
echo "copy done"
