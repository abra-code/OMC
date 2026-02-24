./omc_dialog_control --help

```
Usage: omc_dialog_control __NIB_DLG_GUID__ <controlID> <value>

<controlID> is an integer for control tag or special values:
	"omc_window" to specify that the target is dialog window
	"omc_application" to specify that the target is host application
	"omc_workspace" to specify that the target is shared NSWorkspace
Special values:
	omc_enable, omc_disable
	omc_show, omc_hide
	omc_set_value_from_stdin (read from stdin or pipe)
	omc_set_command_id [followed by command id string]
	omc_list_remove_all
	omc_list_append_items [followed by variable number of arguments]
	omc_list_append_items_from_file [followed by file name]
	omc_list_append_items_from_stdin (read from stdin or pipe)
	omc_list_set_items [followed by variable number of arguments]
	omc_list_set_items_from_file [followed by file name]
	omc_list_set_items_from_stdin (read from stdin or pipe)
	omc_table_set_columns [followed by column names - variable num of args]
	omc_table_set_column_widths [followed by column widths - variable num of args]
	omc_table_remove_all_rows
	omc_table_prepare_empty (like omc_table_remove_all_rows but without refresh)
	omc_table_add_rows [followed by tab-separated row strings]
	omc_table_add_rows_from_file [followed by file name - tab separated data]
	omc_table_add_rows_from_stdin (read from stdin or pipe - tab separated data)
	omc_table_set_rows [followed by tab-separated row strings]
	omc_table_set_rows_from_file [followed by file name - tab separated data]
	omc_table_set_rows_from_stdin (read from stdin or pipe - tab separated data)
	omc_select (brings dialog window or app to front, sets control focus)
	omc_terminate_ok (close dialog with OK message)
	omc_terminate_cancel (close dialog with Cancel message)
	omc_resize [followed by 2 space separated numbers] (for dialog window or controls)
	omc_move [followed by 2 space separated numbers] (for dialog window or controls)
	omc_scroll [followed by 2 space separated numbers] (for view within NSScrollerView)
	omc_invoke [followed by space separated ObjC message] (may be sent to control or window)
	omc_set_property <property_key> <value> (ActionUI only; value is a string or a JSON fragment)
	omc_set_state <state_key> <value> (ActionUI only; value is a string or JSON fragment)

Examples:
omc_dialog_control __NIB_DLG_GUID__ 4 "hello world!"
omc_dialog_control __NIB_DLG_GUID__ 2 omc_disable
omc_dialog_control __NIB_DLG_GUID__ 1 omc_set_command_id "Exec"
omc_dialog_control __NIB_DLG_GUID__ 3 omc_list_remove_all
omc_dialog_control __NIB_DLG_GUID__ 3 omc_list_append_items "Item 1" "Item 2"
omc_dialog_control __NIB_DLG_GUID__ 3 omc_list_append_items_from_file items.txt
ls | omc_dialog_control __NIB_DLG_GUID__ 3 omc_list_append_items_from_stdin

omc_dialog_control __NIB_DLG_GUID__ 5 omc_table_set_columns "A" omc_hidden_column "B" "C"
omc_dialog_control __NIB_DLG_GUID__ 5 omc_table_set_column_widths 90 0 50 80
omc_dialog_control __NIB_DLG_GUID__ 5 omc_table_remove_all_rows
omc_dialog_control __NIB_DLG_GUID__ 5 omc_table_add_rows "11	Hidden1	12	13" "21	Hidden2	22	23"
omc_dialog_control __NIB_DLG_GUID__ 5 omc_table_add_rows_from_file mydata.tsv
cat mydata.tsv | omc_dialog_control __NIB_DLG_GUID__ 5 omc_table_add_rows_from_stdin
omc_dialog_control __NIB_DLG_GUID__ omc_window omc_resize 600 200
omc_dialog_control __NIB_DLG_GUID__ 2 omc_move 20 20
omc_dialog_control __NIB_DLG_GUID__ 4 omc_scroll 0 0
omc_dialog_control __NIB_DLG_GUID__ omc_window omc_terminate_cancel
omc_dialog_control __NIB_DLG_GUID__ 2 omc_invoke setAlignment: 2
omc_dialog_control __ACTIONUI_WINDOW_UUID__ 1 omc_set_property "columns" '["Name","Action"]'
omc_dialog_control __ACTIONUI_WINDOW_UUID__ 2 omc_set_property "disabled" true
omc_dialog_control __ACTIONUI_WINDOW_UUID__ 4 omc_set_state "isLoading" true
omc_dialog_control __ACTIONUI_WINDOW_UUID__ 4 omc_set_state "label" "Hello"
```
