---
id: ui-dialog
level: 1
flavors: [claude, capable, lite]
---

## UI Dialogs

OMC applets have two dialog paradigms. Most new applets should use ActionUI JSON.

### ActionUI JSON (recommended, OMC 5.0+, macOS 14.6+)

A JSON file in `Contents/Resources/Base.lproj/` defines the UI using the ActionUI framework. Connect it to a command via `ACTIONUI_WINDOW` in `Command.plist`:

```xml
<key>ACTIONUI_WINDOW</key>
<dict>
    <key>JSON_NAME</key><string>MainWindow</string>
    <key>INIT_SUBCOMMAND_ID</key><string>MyApp.main.init</string>
</dict>
```

**For ActionUI JSON format** (element types, properties, layout patterns) — read the ActionUI skill. The OMC-specific concerns are:

- `actionID` property value on buttons/pickers/etc. is the `COMMAND_ID` of the handler script that runs on click
- `valueChangeActionID` fires as the value changes (e.g., every keystroke in a TextField)
- Window UUID is `$OMC_ACTIONUI_WINDOW_UUID`
- Read element values via `$OMC_ACTIONUI_VIEW_<id>_VALUE`
- `INIT_SUBCOMMAND_ID` fires when the window loads — populate tables, pickers, and initial state here

**Init script pattern:**

```bash
# MyApp.main.init.sh
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.myapp.sh"

# Populate a picker (element id=20)
"$dialog_tool" "$OMC_ACTIONUI_WINDOW_UUID" 20 \
  omc_set_property "options" '["Option A","Option B","Option C"]'

# Enable a button that starts disabled (element id=10)
"$dialog_tool" "$OMC_ACTIONUI_WINDOW_UUID" 10 omc_enable
```

### NIB Dialogs (legacy — do not use for new applets)

Nib (Interface Builder) dialogs predate ActionUI. `.nib` files can only be edited in Xcode, so agents cannot work on them directly. When maintaining an *existing* NIB applet: the window UUID is `$OMC_NIB_DLG_GUID`, control values arrive as `$OMC_NIB_DIALOG_CONTROL_<tag>_VALUE`, and the dialog attaches via a `NIB_DIALOG` dict in the command manifest. Full reference: `docs/Nib-Guide.md` and `docs/omc_controls_user_defined_runtime_attributes.md`.
