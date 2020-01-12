#!/bin/sh

new_url="$OMC_NIB_DIALOG_CONTROL_1_VALUE"
"$OMC_OMC_SUPPORT_PATH/omc_dialog_control" "$OMC_NIB_DLG_GUID" 2 "$new_url"
