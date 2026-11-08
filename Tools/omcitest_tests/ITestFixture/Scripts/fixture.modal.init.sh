#!/bin/bash
# The blocking window's INIT_SUBCOMMAND_ID: fills its table.
printf 'alpha\nbeta\n' | "$OMC_OMC_SUPPORT_PATH/omc_dialog_control" "$OMC_ACTIONUI_WINDOW_UUID" 7 omc_table_set_rows_from_stdin
