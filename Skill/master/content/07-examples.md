---
id: examples
level: 1
flavors: [lite]
---

## Examples

### Example 1: Contextual menu file action

A command that shows file info when right-clicking a file in Finder.

`Command.plist` entry:
```xml
<dict>
    <key>NAME</key><string>ShowInfo</string>
    <key>COMMAND_ID</key><string>ShowInfo.main</string>
    <key>EXECUTION_MODE</key><string>exe_script_file_with_output_window</string>
    <key>ACTIVATION_MODE</key><string>act_file_or_folder</string>
</dict>
```

`Scripts/ShowInfo.main.sh`:
```bash
echo "=== File Info ==="
echo "Path: $OMC_OBJ_PATH"
/usr/bin/stat -x "$OMC_OBJ_PATH"
```

OMC sets `$OMC_OBJ_PATH` to the right-clicked file's path. The output window shows stdout.

---

### Example 2: ActionUI dialog applet

An applet with a persistent window containing a text field and button.

`Command.plist`:
```xml
<!-- Main command: opens the window when the app launches. No COMMAND_ID. -->
<dict>
    <key>NAME</key><string>MyTool</string>
    <key>EXECUTION_MODE</key><string>exe_script_file</string>
    <key>ACTIONUI_WINDOW</key>
    <dict>
        <key>JSON_NAME</key><string>MainWindow</string>
        <key>IS_BLOCKING</key><false/>
        <key>INIT_SUBCOMMAND_ID</key><string>MyTool.main.init</string>
    </dict>
</dict>
<!-- Subcommand: fires when the button or text field actionID is triggered. -->
<dict>
    <key>NAME</key><string>MyTool</string>
    <key>COMMAND_ID</key><string>MyTool.go</string>
    <key>EXECUTION_MODE</key><string>exe_script_file</string>
</dict>
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
