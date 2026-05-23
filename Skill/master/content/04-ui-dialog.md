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

### NIB Dialogs (AppKit, Interface Builder)

Nib files define UI using AppKit controls. Edit `.nib` files in Xcode via Interface Builder. Use the "Edit" button in AppletBuilder's UI Files or Scripts tabs to open a file in the configured external editor.

**Three steps to make a control interactive:**

1. Rename its class from the standard AppKit version to the OMC version in Xcode's Identity Inspector:

   | Standard class | OMC class |
   |----------------|-----------|
   | `NSButton` | `OMCButton` |
   | `NSTextField` | `OMCTextField` |
   | `NSTableView` | `OMCTableView` |
   | `NSPopUpButton` | `OMCPopUpButton` |
   | `NSSlider` | `OMCSlider` |
   | `NSTextView` | `OMCTextView` |
   | `NSView` (web content) | `OMCWebKitView` |

   Static labels, images, and separators do not need OMC class names.

2. Set the control's **tag** (Identity Inspector → View → Tag) to a non-zero integer. This is the numeric ID scripts use to read/write the control. Some classes (`OMCBox`, `OMCIKImageView`, `OMCPDFView`, `OMCProgressIndicator`, `OMCTextView`, `OMCView`, `OMCWebKitView`) have no native `tag` attribute — add `tag` (Number) as a User Defined Runtime Attribute instead.

3. Add User Defined Runtime Attributes in the Identity Inspector as needed:
   - `commandID` (String) — `COMMAND_ID` to fire when the control is activated (for tables use `selectionCommandID` / `doubleClickCommandID`)
   - `escapingMode` (String) — how the control's value is escaped for `__FOO__` substitution (e.g. `esc_with_backslash`, `esc_wrap_with_single_quotes_for_shell`); not needed when reading via env vars

4. Access the value in scripts via `$OMC_NIB_DIALOG_CONTROL_<tag>_VALUE`.

Connect the nib to a command via `NIB_DIALOG` in `Command.plist` (see execution-modes section for the full key reference). The window UUID for NIB scripts is `$OMC_NIB_DLG_GUID`.

For full NIB documentation: `docs/Nib-Guide.md` and `docs/omc_controls_user_defined_runtime_attributes.md`.
