# OMC Runtime Context Reference

## Introduction

This document lists **all special words** (`__FOO__`) and their corresponding **environment variables** (`$OMC_FOO`) that the OMC engine resolves at runtime.  
The list is derived **directly** from the source files:

* `AbracodeFramework/CommandDescription.cp` – core substitution and export logic  
* `AbracodeFramework/NibDialogControl.cp` – NIB / WebView parsing  

### How the engine works

| Step | What happens |
|------|--------------|
| **1. Substitution** | Every `__FOO__` separate string in a command array (`COMMAND`, `NAME`, `WARNING`, etc.) is replaced with its resolved value **before** execution. |
| **2. Automatic Export** | The following variables are **always exported** (regardless of scanning):<br>`$OMC_OBJ_TEXT`, `$OMC_OBJ_PATH`, `$OMC_OMC_RESOURCES_PATH`, `$OMC_OMC_SUPPORT_PATH`, `$OMC_APP_BUNDLE_PATH`, `$OMC_NIB_DLG_GUID`, `$OMC_CURRENT_COMMAND_GUID`. |
| **3. Export detection** | For all other variables, the engine scans the `COMMAND` array for the literal string `OMC_FOO`. If found, the resolved value is exported (for modes that support env vars). |
| **4. External scripts** | `exe_script_file` scripts are **not** scanned. Force export via comment trick or `ENVIRONMENT_VARIABLES`. |
| **5. `NAME` arrays** | Only `__FOO__` works in dynamic labels – env vars are not expanded. |

---

## Special Words & Environment Variables

| Category | Special Word | Environment Variable | Description | Export |
|----------|--------------|----------------------|-------------|--------|
| **Object** | `__OBJ_PATH__` | `$OMC_OBJ_PATH` | Full path (escaped). | **Always** |
| **Object** | `__OBJ_TEXT__` | `$OMC_OBJ_TEXT` | Selected text (or clipboard). | **Always** |
| **Object** | `__OBJ_NAME__` | `$OMC_OBJ_NAME` | Base name (folder ends with `/`). | Scanned |
| **Object** | `__OBJ_NAME_NO_EXTENSION__` | `$OMC_OBJ_NAME_NO_EXTENSION` | Name without extension. | Scanned |
| **Object** | `__OBJ_EXTENSION_ONLY__` | `$OMC_OBJ_EXTENSION_ONLY` | Extension only (no dot). | Scanned |
| **Object** | `__OBJ_DISPLAY_NAME__` | `$OMC_OBJ_DISPLAY_NAME` | Localized display name. | Scanned |
| **Object** | `__OBJ_PARENT_PATH__` | `$OMC_OBJ_PARENT_PATH` | Parent directory path. | Scanned |
| **Object** | `__OBJ_COMMON_PARENT_PATH__` | `$OMC_OBJ_COMMON_PARENT_PATH` | Common parent for multiple objects. | Scanned |
| **Object** | `__OBJ_PATH_RELATIVE_TO_COMMON_PARENT__` | `$OMC_OBJ_PATH_RELATIVE_TO_COMMON_PARENT` | Relative path from common parent. | Scanned |
| **Dialog** | `__DLG_INPUT_TEXT__` | `$OMC_DLG_INPUT_TEXT` | Input dialog text. | Scanned |
| **Save As** | `__DLG_SAVE_AS_PATH__` | `$OMC_DLG_SAVE_AS_PATH` | Save-As path. | Scanned |
| **Save As** | `__DLG_SAVE_AS_PARENT_PATH__` | `$OMC_DLG_SAVE_AS_PARENT_PATH` | Save-As parent directory. | Scanned |
| **Save As** | `__DLG_SAVE_AS_NAME__` | `$OMC_DLG_SAVE_AS_NAME` | Save-As filename. | Scanned |
| **Save As** | `__DLG_SAVE_AS_NAME_NO_EXTENSION__` | `$OMC_DLG_SAVE_AS_NAME_NO_EXTENSION` | Save-As name without extension. | Scanned |
| **Save As** | `__DLG_SAVE_AS_EXTENSION_ONLY__` | `$OMC_DLG_SAVE_AS_EXTENSION_ONLY` | Save-As extension only. | Scanned |
| **Choose File** | `__DLG_CHOOSE_FILE_PATH__` | `$OMC_DLG_CHOOSE_FILE_PATH` | Chosen file path. | Scanned |
| **Choose File** | `__DLG_CHOOSE_FILE_PARENT_PATH__` | `$OMC_DLG_CHOOSE_FILE_PARENT_PATH` | Chosen file parent. | Scanned |
| **Choose File** | `__DLG_CHOOSE_FILE_NAME__` | `$OMC_DLG_CHOOSE_FILE_NAME` | Chosen file name. | Scanned |
| **Choose File** | `__DLG_CHOOSE_FILE_NAME_NO_EXTENSION__` | `$OMC_DLG_CHOOSE_FILE_NAME_NO_EXTENSION` | Chosen file name without extension. | Scanned |
| **Choose File** | `__DLG_CHOOSE_FILE_EXTENSION_ONLY__` | `$OMC_DLG_CHOOSE_FILE_EXTENSION_ONLY` | Chosen file extension only. | Scanned |
| **Choose Folder** | `__DLG_CHOOSE_FOLDER_PATH__` | `$OMC_DLG_CHOOSE_FOLDER_PATH` | Chosen folder path. | Scanned |
| **Choose Folder** | `__DLG_CHOOSE_FOLDER_PARENT_PATH__` | `$OMC_DLG_CHOOSE_FOLDER_PARENT_PATH` | Chosen folder parent. | Scanned |
| **Choose Folder** | `__DLG_CHOOSE_FOLDER_NAME__` | `$OMC_DLG_CHOOSE_FOLDER_NAME` | Chosen folder name. | Scanned |
| **Choose Folder** | `__DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION__` | `$OMC_DLG_CHOOSE_FOLDER_NAME_NO_EXTENSION` | Chosen folder name without extension. | Scanned |
| **Choose Folder** | `__DLG_CHOOSE_FOLDER_EXTENSION_ONLY__` | `$OMC_DLG_CHOOSE_FOLDER_EXTENSION_ONLY` | Chosen folder extension only. | Scanned |
| **Choose Object** | `__DLG_CHOOSE_OBJECT_PATH__` | `$OMC_DLG_CHOOSE_OBJECT_PATH` | Chosen object path. | Scanned |
| **Choose Object** | `__DLG_CHOOSE_OBJECT_PARENT_PATH__` | `$OMC_DLG_CHOOSE_OBJECT_PARENT_PATH` | Chosen object parent. | Scanned |
| **Choose Object** | `__DLG_CHOOSE_OBJECT_NAME__` | `$OMC_DLG_CHOOSE_OBJECT_NAME` | Chosen object name. | Scanned |
| **Choose Object** | `__DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION__` | `$OMC_DLG_CHOOSE_OBJECT_NAME_NO_EXTENSION` | Chosen object name without extension. | Scanned |
| **Choose Object** | `__DLG_CHOOSE_OBJECT_EXTENSION_ONLY__` | `$OMC_DLG_CHOOSE_OBJECT_EXTENSION_ONLY` | Chosen object extension only. | Scanned |
| **System** | `__OMC_RESOURCES_PATH__` | `$OMC_OMC_RESOURCES_PATH` | Path to OMC framework Resources. | **Always** |
| **System** | `__OMC_SUPPORT_PATH__` | `$OMC_OMC_SUPPORT_PATH` | Path to OMC support files. | **Always** |
| **System** | `__APP_BUNDLE_PATH__` | `$OMC_APP_BUNDLE_PATH` | Applet bundle path (preferred). | **Always** |
| **System** | `__MY_EXTERNAL_BUNDLE_PATH__` | `$OMC_MY_EXTERNAL_BUNDLE_PATH` | External `.omc` bundle path. | Scanned |
| **Dialog** | `__NIB_DLG_GUID__` | `$OMC_NIB_DLG_GUID` | Unique NIB dialog instance GUID. | **Always** |
| **Dialog** | `__ACTIONUI_WINDOW_UUID__` | `$OMC_ACTIONUI_WINDOW_UUID` | Unique ActionUI window UUID. OMC 5.0 | **Always** |
| **ActionUI Trigger** | `__ACTIONUI_TRIGGER_VIEW_ID__` | `$OMC_ACTIONUI_TRIGGER_VIEW_ID` | ViewID of the ActionUI control that fired an action. Available only when subcommand is dispatched from a control action. | **Always (when set)** |
| **ActionUI Trigger** | `__ACTIONUI_TRIGGER_VIEW_PART_ID__` | `$OMC_ACTIONUI_TRIGGER_VIEW_PART_ID` | ViewPartID of the control event (e.g. row index for table row tap). Available only when subcommand is dispatched from a control action. | **Always (when set)** |
| **ActionUI Trigger** | `__ACTIONUI_TRIGGER_CONTEXT__` | `$OMC_ACTIONUI_TRIGGER_CONTEXT` | Opaque context payload from the ActionUI control event (string, JSON, or number). Available only when subcommand is dispatched from a control action AND the control provided context data. | **Always (when set)** |
| **System** | `__CURRENT_COMMAND_GUID__` | `$OMC_CURRENT_COMMAND_GUID` | Unique command execution GUID. | **Always** |
| **Frontmost** | `__FRONT_PROCESS_ID__` | `$OMC_FRONT_PROCESS_ID` | PID of frontmost app. | Scanned |
| **Frontmost** | `__FRONT_APPLICATION_NAME__` | `$OMC_FRONT_APPLICATION_NAME` | Name of frontmost app. | Scanned |

---

### Deprecated Synonyms

| Special Word | Environment Variable | Notes |
|--------------|----------------------|-------|
| `__MY_HOST_BUNDLE_PATH__` | `$OMC_MY_HOST_BUNDLE_PATH` | Deprecated |
| `__INPUT_TEXT__` | `$OMC_INPUT_TEXT` | Use `OMC_DLG_INPUT_TEXT` |
| `__OBJ_PATH_NO_EXTENSION__` | `$OMC_OBJ_PATH_NO_EXTENSION` | Not needed |
| `__PASSWORD__` | `$OMC_PASSWORD` | Use `OMC_DLG_INPUT_TEXT` with password input |
| `__SAVE_AS_PATH__` | `$OMC_SAVE_AS_PATH` | Use `OMC_DLG_SAVE_AS_PATH` |
| `__SAVE_AS_PARENT_PATH__` | `$OMC_SAVE_AS_PARENT_PATH` | Use `OMC_DLG_SAVE_AS_PARENT_PATH` |
| `__SAVE_AS_FILE_NAME__` | `$OMC_SAVE_AS_FILE_NAME` | Use `OMC_DLG_SAVE_AS_NAME` |
| `__MY_BUNDLE_PATH__` | `$OMC_MY_BUNDLE_PATH` | Use `$OMC_APP_BUNDLE_PATH` |

---

## Forcing Exports in `exe_script_file`

```xml
<dict>
  <key>COMMAND_ID</key>
  <string>my_action</string>
  <key>EXECUTION_MODE</key>
  <string>exe_script_file</string>
  <key>COMMAND</key>
  <array>
    <!-- Force export of non-auto variable -->
    <string># OMC_OBJ_NAME</string>
  </array>
  <key>ENVIRONMENT_VARIABLES</key>
  <dict>
    <key>OMC_DLG_INPUT_TEXT</key>
    <string></string>
  </dict>
</dict>
```

Script:
```bash
#!/bin/bash
echo "File: ${OMC_OBJ_NAME}"
echo "Input: ${OMC_DLG_INPUT_TEXT}"
```

---

## Dynamic `NAME` (menu / button label)

```xml
<key>NAME</key>
<array>
  <string>Process: </string>
  <string>__OBJ_NAME__</string>
</array>
```

---

## Dynamic Control Access

### NIB Dialog Controls

Access NIB dialog control values using dynamic special words:

| Special Word | Environment Variable | Description |
|--------------|---------------------|-------------|
| `__NIB_DIALOG_CONTROL_<ID>_VALUE__` | `OMC_NIB_DIALOG_CONTROL_<ID>_VALUE` | Value of NIB control with given tag. |
| `__NIB_TABLE_<ID>_COLUMN_<COL>_VALUE__` | `OMC_NIB_TABLE_<ID>_COLUMN_<COL>_VALUE` | Table selected cell value. |
| `__NIB_TABLE_<ID>_COLUMN_<COL>_ALL_ROWS__` | `OMC_NIB_TABLE_<ID>_COLUMN_<COL>_ALL_ROWS` | All rows in table column (expensive). |
| `__NIB_WEBVIEW_<ID>_ELEMENT_<ELEM>_VALUE__` | `OMC_NIB_WEBVIEW_<ID>_ELEMENT_<ELEM>_VALUE` | WebView element value. |

### ActionUI Views (OMC 5.0 or higher)

Access ActionUI view values using dynamic special words:

| Special Word | Environment Variable | Description |
|--------------|---------------------|-------------|
| `__ACTIONUI_VIEW_N_VALUE__` | `OMC_ACTIONUI_VIEW_N_VALUE` | Value of ActionUI view with given integer ID. |
| `__ACTIONUI_TABLE_<ID>_COLUMN_<N>_VALUE__` | `OMC_ACTIONUI_TABLE_<ID>_COLUMN_<N>_VALUE` | ActionUI Table selected row, column N (1-based). |
| `__ACTIONUI_TABLE_<ID>_COLUMN_<N>_ALL_ROWS__` | `OMC_ACTIONUI_TABLE_<ID>_COLUMN_<N>_ALL_ROWS` | ActionUI Table all rows in column N (1-based). |
| `__ACTIONUI_TABLE_<ID>_COLUMN_0_VALUE__` | `OMC_ACTIONUI_TABLE_<ID>_COLUMN_0_VALUE` | ActionUI Table selected row, all columns combined (tab-separated). |

> **Note**: Table column indexes are **1-based** (column 1, 2, 3, ...). Column 0 is special - it returns all columns combined as a tab-separated string.

### ActionUI Control Trigger Context (OMC 5.0+)

When a subcommand is dispatched by tapping / clicking an ActionUI control (button, table row, picker option, etc.), three context variables become available in the child process environment:

| Special Word | Environment Variable | Description | Availability |
|--------------|---------------------|---|---|
| `__ACTIONUI_TRIGGER_VIEW_ID__` | `$OMC_ACTIONUI_TRIGGER_VIEW_ID` | The integer ID of the ActionUI control that fired the action. | Only when dispatched from a control action. |
| `__ACTIONUI_TRIGGER_VIEW_PART_ID__` | `$OMC_ACTIONUI_TRIGGER_VIEW_PART_ID` | The integer part ID within that control — typically a row or column index. | Only when dispatched from a control action. |
| `__ACTIONUI_TRIGGER_CONTEXT__` | `$OMC_ACTIONUI_TRIGGER_CONTEXT` | The opaque context payload from the control, if any. Serialized as string, number, or compact JSON. | Only when dispatched from a control action AND the control provided context data. |

**When are these available?**

These variables are **only present** when the subcommand is dispatched by a control action. They are **not** available when the subcommand is triggered by:
- Dialog initialization (`init` subcommand)
- Command activation (`activate` subcommand)
- Command deactivation (`deactivate` subcommand)
- Dialog or window close

**How to check if context is available:**

```bash
if [ -n "$OMC_ACTIONUI_TRIGGER_VIEW_ID" ]; then
    # Subcommand was triggered from a control action
    echo "View: $OMC_ACTIONUI_TRIGGER_VIEW_ID, Part: $OMC_ACTIONUI_TRIGGER_VIEW_PART_ID"
    echo "View Context: $OMC_ACTIONUI_TRIGGER_CONTEXT"
fi
```

**Example: Handling a table row tap**

```bash
#!/bin/bash
# A table changed selected row

if [ -n "$OMC_ACTIONUI_TRIGGER_VIEW_ID" ]; then
    view_id="${OMC_ACTIONUI_TRIGGER_VIEW_ID}"
    view_part_id="${OMC_ACTIONUI_TRIGGER_VIEW_PART_ID}"
    view_context_json="${OMC_ACTIONUI_TRIGGER_CONTEXT}"    
	echo "Table ${view_id} changed selected row"
	echo "Table row selection context: ${view_context_json}"
fi
```

**Serialization of `$OMC_ACTIONUI_TRIGGER_CONTEXT`:**

The context is an opaque value provided by the ActionUI control and is serialized as follows:
- **String** → passed as-is
- **Number** → converted to string form (e.g., `"42"`)
- **Dictionary / Array** → serialized as compact JSON (no pretty-printing)
- **Other** → stringified via description
- **nil / absent** → env var is not exported (variable is absent from environment)

**Important:** `$OMC_ACTIONUI_TRIGGER_VIEW_ID` and `$OMC_ACTIONUI_TRIGGER_VIEW_PART_ID` are always available when any control action fires, but `$OMC_ACTIONUI_TRIGGER_CONTEXT` may or may not be present depending on whether the control provided data.

---

> ## Summary of Best Practices:
> - **Prefer `$OMC_FOO`** in scripts – always quote `"${OMC_FOO}"`.  
> - **Use `__FOO__`** only in `NAME` arrays or for `exe_system`/`exe_applescript`.  
> - **Do not** use deprecated synonyms in new code.  
> - **Force export** for **non-auto** variables in `exe_script_file`.  


---
