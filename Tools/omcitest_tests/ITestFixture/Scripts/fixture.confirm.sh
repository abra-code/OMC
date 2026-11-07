#!/bin/bash
"$OMC_OMC_SUPPORT_PATH/alert" --level caution --title "ITestFixture" --ok "Delete" --cancel "Keep" "Delete the report?"
answer=$?
echo "answer:${answer}"
echo "support:${OMC_OMC_SUPPORT_PATH}"
