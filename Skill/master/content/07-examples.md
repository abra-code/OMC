---
id: examples
level: 1
flavors: [lite]
---

## Examples

### Example 1: Contextual menu file action

A command that shows file info when right-clicking a file in Finder.

`Command.json` entry:
```json
{
  "NAME": "ShowInfo",
  "COMMAND_ID": "ShowInfo.main",
  "EXECUTION_MODE": "exe_script_file_with_output_window",
  "ACTIVATION_MODE": "act_file_or_folder"
}
```

`Scripts/ShowInfo.main.sh`:
```bash
echo "=== File Info ==="
echo "Path: $OMC_OBJ_PATH"
/usr/bin/stat -x "$OMC_OBJ_PATH"
```

The Command Engine sets `$OMC_OBJ_PATH` to the right-clicked file's path. The output window shows stdout.

---

### Example 2: ActionUI dialog applet

An applet with a persistent window containing a text field and button.

`Command.json` (the first command is the main command: no `COMMAND_ID`, it opens the window when the app launches; the second is the subcommand the button and the text field fire):
```json
{
  "COMMAND_LIST": [
    {
      "NAME": "MyTool",
      "EXECUTION_MODE": "exe_script_file",
      "ACTIONUI_WINDOW": {
        "JSON_NAME": "MainWindow",
        "IS_BLOCKING": false,
        "INIT_SUBCOMMAND_ID": "MyTool.main.init"
      }
    },
    {
      "NAME": "MyTool",
      "COMMAND_ID": "MyTool.go",
      "EXECUTION_MODE": "exe_script_file"
    }
  ],
  "VERSION": 2
}
```

`Resources/Base.lproj/MainWindow.json` (ActionUI JSON — see ActionUI skill for format):
```json
{
  "type": "VStack",
  "properties": {"spacing": 12, "padding": 16},
  "children": [
    {"type": "TextField", "id": 1, "properties": {"title": "Input", "actionID": "MyTool.go"}},
    {"type": "Button", "id": 2, "properties": {"title": "Go", "buttonStyle": "borderedProminent", "actionID": "MyTool.go"}}
  ]
}
```

`Scripts/MyTool.main.init.sh` (runs when window opens):
```bash
dialog_tool="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
"$dialog_tool" "$OMC_ACTIONUI_WINDOW_UUID" 2 omc_enable
```

`Scripts/MyTool.go.sh` (runs when button pressed or Enter in text field):
```bash
dialog_tool="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
alert_tool="$OMC_OMC_SUPPORT_PATH/alert"

# Read the text field value (id=1)
input="$OMC_ACTIONUI_VIEW_1_VALUE"

"$alert_tool" --level info --title "MyTool" "You entered: $input"
```

Key points:
- The main command has no `COMMAND_ID` — the engine runs `Scripts/<NAME>.main.<ext>` on launch and the attached `ACTIONUI_WINDOW` opens the window.
- `ACTIONUI_WINDOW.JSON_NAME` is the JSON filename without `.json` (in `Resources/Base.lproj/`).
- `INIT_SUBCOMMAND_ID` fires when the window loads.
- `actionID` in JSON matches `COMMAND_ID` of the handler script.
- `$OMC_ACTIONUI_VIEW_<id>_VALUE` reads element values by `id`.
