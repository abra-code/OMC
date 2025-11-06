# OMC Services Reference

## Overview

OMC applets integrate with macOS **Services** via the `NSServices` array in `Info.plist`. The OMC engine uses a centralized handler to process all service invocations, routing them to the appropriate command based on the `NSUserData` value.

**Key OMC-Specific Requirements** (must be exact):

| Key           | Value                     | Required | Description |
|---------------|---------------------------|----------|-------------|
| `NSMessage`   | `"runOMCService"`         | Yes      | Fixed selector recognized by the OMC engine |
| `NSPortName`  | `"OMCService"`            | Yes      | Fixed Mach port name for service communication |
| `NSUserData`  | Command identifier        | Yes      | Either `NAME` (command group) or `COMMAND_ID` (specific handler) |

The OMC engine listens on the `OMCService` port upon applet launch. When a service is selected, macOS sends the `runOMCService` message. The engine extracts `NSUserData`, resolves it to a command, processes input from the pasteboard based on `NSSendTypes`, sets environment variables, and executes the command.

## `NSUserData` Resolution

- **`NAME`**: Refers to the top-level command group. Suitable when the command has no subcommands or when invoking the default handler.
- **`COMMAND_ID`**: unique string identifier for a specific subcommand. **Preferred** when multiple handlers exist in a command group, as it ensures precise dispatch.

> **Recommendation**: Use `COMMAND_ID` to avoid ambiguity and ensure the exact handler is executed.

## Input Environment Variables

| Pasteboard Type         | Environment Variable | Description |
|-------------------------|----------------------|-------------|
| `NSFilenamesPboardType` | `$OMC_OBJ_PATH`      | file/folder path or a list of file/folder paths |
| `NSStringPboardType`    | `$OMC_OBJ_TEXT`      | Selected text content |

- For multiple files: Iterate over `$OMC_OBJ_PATH`
- Text is also available via stdin if the command uses `STANDARD_INPUT_PIPE` with `__OBJ_TEXT__`.

## Output Handling

- **Return data**: Output to **stdout** — returned to the caller if `NSReturnTypes` includes `NSStringPboardType`.
- **Action-only**: Omit `NSReturnTypes` if no data return is needed.

## Example `Info.plist` Entry

```xml
<key>NSServices</key>
<array>
    <dict>
        <key>NSMenuItem</key>
        <dict>
            <key>default</key>
            <string>Show File Paths</string>
        </dict>
        <key>NSMessage</key>
        <string>runOMCService</string>
        <key>NSPortName</key>
        <string>OMCService</string>
        <key>NSUserData</key>
        <string>show.file.paths</string>  <!-- COMMAND_ID example -->
        <key>NSSendTypes</key>
        <array>
            <string>NSFilenamesPboardType</string>
        </array>
        <key>NSReturnTypes</key>
        <array>
            <string>NSStringPboardType</string>
        </array>
    </dict>
</array>
```

## Real-World Examples

### Find.app at [FindApp](https://github.com/abra-code/FindApp)
- `NSUserData`: `find.new` (corresponding to `COMMAND_ID` in Command.plist)
- `NSSendTypes`: `NSFilenamesPboardType`
- Input: `$OMC_OBJ_PATH` as a directory to search

### Xattr.app at [XattrApp](https://github.com/abra-code/XattrApp)
- `NSUserData`: `Xattr` (corresponding to `NAME` in command description)
- `NSSendTypes`: `NSFilenamesPboardType`
- Input: `$OMC_OBJ_PATH` for file or folder to view extended attributes. Multiple selections processed separately.

---


**Summary**  
All OMC services **must** include:

```xml
<key>NSMessage</key>
<string>runOMCService</string>
<key>NSPortName</key>
<string>OMCService</string>
<key>NSUserData</key>
<string>CommandNameOrID</string>
```
