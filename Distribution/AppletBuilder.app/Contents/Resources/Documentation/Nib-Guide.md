# Nib UI Files in OMC Applets

Nib files (`.nib`) are Interface Builder documents used to define UI with AppKit controls. They are the traditional way to build OMC applet dialogs before ActionUI JSON was introduced.

## Editing

Nib files must be edited in **Xcode** using Interface Builder. Use the "Edit" button in AppletBuilder to open the selected nib in Xcode.

**Recommended format:** Use bundled `.nib` (a directory containing `designable.nib` and `keyedobjects.nib`). This format allows in-place editing — Xcode can open and save directly without recompilation.

## Making Controls Interactive with OMC

Standard AppKit controls (NSButton, NSTextField, etc.) inserted in Interface Builder are not connected to OMC commands. To make a control interactive, **rename its class** from the NS version to the corresponding OMC version in Xcode's Identity Inspector:

| Standard Class | OMC Class | Purpose |
|---------------|-----------|---------|
| NSButton | OMCButton | Triggers a command on click |
| NSTextField | OMCTextField | Text input with command on Enter |
| NSSecureTextField | OMCSecureTextField | Password input |
| NSComboBox | OMCComboBox | Editable combo box |
| NSPopUpButton | OMCPopUpButton | Popup menu |
| NSSearchField | OMCSearchField | Search field |
| NSSlider | OMCSlider | Slider control |
| NSTableView | OMCTableView | Table with selection/double-click commands |
| NSTextView | OMCTextView | Multi-line text |
| NSImageView | OMCImageView | Image display |
| NSView (Custom View) | OMCWebKitView | Web content (see note below) |
| NSBox | OMCBox | Container box |
| NSView | OMCView | Generic container |
| NSProgressIndicator | OMCProgressIndicator | Progress bar |

**Purely decorational controls** (labels, static images, separators) do not need to be renamed to OMC versions.

**OMCWebKitView note:** Do not insert a WKWebView in Interface Builder. Apple's WKWebView cannot be reconfigured after instantiation from a nib. Instead, insert a **Custom View** (NSView) and change its class to `OMCWebKitView`. The OMC class creates and manages the WKWebView internally.

## Connecting Controls to Commands

After renaming a control to its OMC class, add **User Defined Runtime Attributes** in Xcode's Identity Inspector:

- **commandID** (String) — the command identifier to execute when the control is activated
- **escapingMode** (String) — how to escape the control's value for the script
- **tag** (Number) — numeric identifier for reading/writing control values from scripts

**When is a tag needed?** Only when your script needs to interact with the control — reading its value via environment variables or setting its value/state via `omc_dialog_control`. An OMCButton that simply triggers a command but is never enabled/disabled/hidden from a script does not need a unique tag.

For detailed property reference, see:

- [OMC Controls — User Defined Runtime Attributes](omc_controls_user_defined_runtime_attributes.md)

## Accessing Control Values from Scripts

Control values are available as environment variables:

- `$OMC_NIB_DIALOG_CONTROL_<ID>_VALUE` — value of control with given tag
- `$OMC_NIB_TABLE_<ID>_COLUMN_<n>_VALUE` — table column value (1-based)

## Escaping Modes

| Mode | Description |
|------|-------------|
| `esc_none` | No escaping |
| `esc_with_backslash` | Backslash-escape special characters |
| `esc_with_percent` | Percent-encode special characters |
| `esc_with_percent_all` | Percent-encode all characters |
| `esc_for_applescript` | Escape for AppleScript strings |
| `esc_wrap_with_single_quotes_for_shell` | Wrap in single quotes for shell |

## Command.plist Integration

Nib dialogs are connected via `NIB_DIALOG` dictionary in Command.plist:

```xml
<key>NIB_DIALOG</key>
<dict>
    <key>NIB_NAME</key>
    <string>MyDialog</string>
    <key>INIT_SUBCOMMAND_ID</key>
    <string>MyApp.dialog.init</string>
    <key>END_OK_SUBCOMMAND_ID</key>
    <string>MyApp.dialog.ok</string>
    <key>END_CANCEL_SUBCOMMAND_ID</key>
    <string>MyApp.dialog.cancel</string>
</dict>
```
