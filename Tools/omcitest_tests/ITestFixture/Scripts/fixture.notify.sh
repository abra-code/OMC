#!/bin/bash
"$OMC_OMC_SUPPORT_PATH/notify" --title "ITestFixture" "Export finished"
echo "notified:$?"
# And show the result, as an export would: open is omcitest's recording stand-in, so nothing opens
"$OMC_OMC_SUPPORT_PATH/open" -R "$OMC_APP_BUNDLE_PATH"
