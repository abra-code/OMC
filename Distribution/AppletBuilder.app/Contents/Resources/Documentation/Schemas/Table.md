# ActionUI.Table

JSON schema and usage documentation for `Table`.

```jsonc
// Sources/Views/Table.swift
// JSON specification for ActionUI.Table view (macOS only):
 {
   "type": "Table",
   "id": 1,              // Required: Non-zero positive integer for runtime programmatic interaction and diffing
   "properties": {
     "columns": ["Name", "Action", "Icon"], // Required: Array of strings for column headers
     "columnTypes": [                       // Optional: Per-column type config array. Defaults to all Text.
       { "viewType": "Text" },              // Each entry: { "viewType": "Text"|"Button"|"Image"|"AsyncImage"
       { "viewType": "Button",              // Columns without an entry default to Text.
         "actionContext": "rowIndex",       // "actionContext": "title"|"rowIndex"|"columnIndex"|"rowColumnIndex" (Button only)
         "actionID": "row.action" },        // "actionID": "..." (Button only — fires on button click) }
       { "viewType": "Image",
         "dataInterpretation": "systemName" } // "dataInterpretation": "path"|"systemName"|"assetName"|"resourceName"|"mixed" (Image only)
     ],
     "widths": [100, 80, 40],               // Optional: Array of integers for ideal column widths (resizable; last column fills remaining space)
     "actionID": "table.selection.changed", // Optional: Fires on selection change (all cell types)
     "doubleClickActionID": "table.double.click" // Optional: String for double-click action (context = row index)
   }
 }
   // Note: The Table view is macOS-only, showing a multi-column table with per-column cell types specified by the columnTypes array. If columnTypes is omitted or shorter than columns, missing entries default to Text. Selection is stored as [String] in state["value"], using row IDs for tracking. The table-level actionID fires on selection change. Button columns have their own actionID in their columnTypes entry, fired on click — this cleanly separates selection events from button click events. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties). The applyModifiers implementation is provided by the ActionUIViewConstruction protocol extension. SwiftUI types are explicitly prefixed (e.g., SwiftUI.Table, SwiftUI.TableColumn) to avoid namespace conflicts. Uses TableColumnForEach for dynamic columns on macOS 14.4+. Falls back to a placeholder message for earlier versions.
   // Performance: Child views are strongly typed to avoid AnyView overhead, identified by stable indices in ForEach, optimizing SwiftUI diffing for large tables (e.g., 1000 rows x 50 columns). Image creation uses SwiftUI.Image extension, aligned with Image.swift, to minimize overhead. Ensure state updates are targeted to minimize re-renders.

// Observable state:
//   value ([String])                    Selected row as an array of column strings (first column = display value).
//                                       Access via getElementValue / setElementValue.
//   states["content"]   [[String]]      All table rows; each inner array holds one row's column values.
//                                       Access via getElementRows / setElementRows / appendElementRows /
//                                       clearElementRows / getElementColumnCount.
//   states["selectedRowID"] String?     Stable row ID of the currently selected row; nil when nothing is
//                                       selected. No dedicated public API — use getElementState / setElementState.
```
