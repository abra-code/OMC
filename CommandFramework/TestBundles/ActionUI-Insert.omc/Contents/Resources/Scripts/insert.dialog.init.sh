#!/bin/sh
dialog_tool="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
UUID="$OMC_ACTIONUI_WINDOW_UUID"
LPROJ="$OMC_MY_EXTERNAL_BUNDLE_PATH/Contents/Resources/Base.lproj"

# 1. Append a new Text element into VStack id=10
insert_ok=NO
"$dialog_tool" "$UUID" 10 omc_insert_element "$(cat "$LPROJ/element_append.json")" && insert_ok=YES

# 2. Prepend a new Text element into VStack id=10
insert_prepend_ok=NO
"$dialog_tool" "$UUID" 10 omc_insert_element "$(cat "$LPROJ/element_prepend.json")" children prepend && insert_prepend_ok=YES

# 3. Insert after sibling id=12 into VStack id=10
insert_after_ok=NO
"$dialog_tool" "$UUID" 10 omc_insert_element "$(cat "$LPROJ/element_after.json")" children after:12 && insert_after_ok=YES

# 4. Append a new row into Grid id=5
insert_row_ok=NO
"$dialog_tool" "$UUID" 5 omc_insert_element_row "$(cat "$LPROJ/row_append.json")" && insert_row_ok=YES

# 5. Remove element id=11 (Item A) from VStack id=10
remove_ok=NO
"$dialog_tool" "$UUID" 11 omc_remove_element && remove_ok=YES

# Write init diagnostic atomically
init_file="/tmp/OMC_test_insert_init_${UUID}"
{
    echo "INIT_COMPLETE=YES"
    echo "INSERT_ELEMENT_OK=$insert_ok"
    echo "INSERT_ELEMENT_PREPEND_OK=$insert_prepend_ok"
    echo "INSERT_ELEMENT_AFTER_OK=$insert_after_ok"
    echo "INSERT_ELEMENT_ROW_OK=$insert_row_ok"
    echo "REMOVE_ELEMENT_OK=$remove_ok"
    echo "OMC_ACTIONUI_WINDOW_UUID=$UUID"
} > "${init_file}.tmp"
mv "${init_file}.tmp" "$init_file"
