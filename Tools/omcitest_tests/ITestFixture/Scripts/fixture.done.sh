#!/bin/bash
# The modeless window's Done button: closes its window as OK'd, through omc_dialog_control.
"$OMC_OMC_SUPPORT_PATH/omc_dialog_control" "$OMC_ACTIONUI_WINDOW_UUID" omc_window omc_terminate_ok
