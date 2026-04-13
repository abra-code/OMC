# ActionUI.List

JSON schema and usage documentation for `List`.

```jsonc
// Sources/Views/List.swift
// JSON specification for ActionUI.List view:
  {
    "type": "List",
    "id": 1,              // Required: Non-zero positive integer for runtime programmatic interaction and diffing
    "properties": {
      // Form 1: Homogeneous list of pre-declared types from external data
      "itemType": {                            // Optional: Defaults to { "viewType": "Text" }
        "viewType": "Button",                  // "Text"|"Button"|"Image"|"AsyncImage"
        "actionContext": "rowIndex",           // "title"|"rowIndex" (Button only)
        "actionID": "list.buttonClick",        // Button only — fires on button click
        "dataInterpretation": "systemName"     // "path"|"systemName"|"assetName"|"resourceName"|"mixed" (Image only)
      },
      "actionID": "list.selection.changed",    // Optional: Fires on selection change (all cell types)
      "doubleClickActionID": "list.double.click",  // Optional: String for double-click action (macOS only, context = row index)
      // List styling
      "listStyle": "plain",                   // Optional: list style — platform availability below
                                              //   "automatic"    — all platforms (system default)
                                              //   "plain"        — all platforms
                                              //   "inset"        — iOS, macOS, visionOS
                                              //   "sidebar"      — iOS, macOS, visionOS
                                              //   "grouped"      — iOS, tvOS, visionOS
                                              //   "insetGrouped" — iOS, visionOS only
      // Row styling — applied uniformly to all rows
      "listRowBackground": "blue",            // Optional: Color string (e.g., "blue", "#FF0000") — all platforms
      "listRowSeparator": "hidden",           // Optional: "visible"|"hidden"|"automatic" — iOS/macOS/visionOS only
      "listRowSeparatorTint": "gray",         // Optional: Color string for separator tint — iOS/macOS/visionOS only
      "listRowInsets": 16,                    // Optional: Number for uniform insets or {"top": 8, "leading": 16, "bottom": 8, "trailing": 16}
    },
    // Form 2: Heterogeneous list from embedded JSON
    "children": [                            // Optional: Array of child views for complex lists
      {
        "type": "NavigationLink",
        "id": 10,                            // Recommended: Set unique ID for selection support
        "properties": {
          "title": "Item 1"
        },
        "destination": {                   // Destination must be a full view element
          "type": "Text",
          "properties": { "title": "Item 1 Detail" }
        }
      },
      {
        "type": "Button",
        "id": 11,                            // Recommended: Set unique ID for selection support
        "properties": { "title": "Item 2" }
      }
    ],
    // Form 3: Data-driven list with template (replaces itemType with full ActionUI template)
    "template": {                           // "template" presence activates data-driven template mode; "id" required
      "type": "HStack",
      "children": [
        { "type": "Image", "properties": { "systemName": "$1" } }, // $1, $2, etc. are 1-based data column indexes
        { "type": "Text",  "properties": { "text": "$2" } }
      ]
    }
  }
    // Note: The List can operate in three modes (Form 1, 2, and 3):
    //   1. Homogeneous list: Shows a single-column list of homogeneous views (Text, Button, Image, AsyncImage)
    //      specified by itemType.viewType. Selection is stored as [String] in state, using the item string or id.
    //      The list-level actionID fires on selection change. Button items have their own actionID in itemType,
    //      fired on click — this cleanly separates selection events from button click events. On macOS,
    //      double-click triggers doubleClickActionID with row index as context.
    //   2. Heterogeneous list: Shows a list of arbitrary views defined in the "children" array.
    //      Operates in two sub-modes depending on whether actionID is set:
    //
    //      a) With actionID (selectable mode): List(selection:) binding is enabled using
    //         bidirectional child-ID mapping (same pattern as NavigationSplitView.buildSidebarList).
    //         Selection is stored in model.value as [String] with the stringified child element ID.
    //         actionID fires on selection change. Children should be Labels/Text (not NavigationLinks)
    //         because List(selection:) intercepts taps on iOS.
    //         When used inside NavigationStack with destinations, NavigationStack detects this pattern
    //         and handles push navigation — see NavigationStack.swift.
    //         Row styling (listRowBackground/listRowSeparator/listRowInsets) is applied via
    //         a rowModifier closure passed to SelectionListHelper.buildSelectableList.
    //
    //      b) Without actionID (no-selection mode): No selection binding. NavigationLinks handle
    //         their own taps. Action callbacks:
    //           - Button children: fire their own actionID on tap.
    //           - NavigationLink children: push destinations via NavigationStack.
    //           - Label/Text children: display-only; use Button if tap action is needed.
    //         Row styling properties are applied to each child view.
    //
    //      Note: NavigationSplitView sidebar selection is handled by NavigationSplitView.buildSidebarList(),
    //      which constructs its own List(selection:) — it does not go through this List.buildView path.
    //      Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity,
    //      cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and
    //      applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
    //      The applyModifiers implementation is provided by the ActionUIViewConstruction protocol extension.
    //   3. Template-based list: homogeneous rows of ActionUI views based on pre-declared template
    //      Column text values are assigned to specific sub-view values by index
    //      Column indexes are 1-based: $1 (col 0), $2 (col 1), $N (col N-1), $0 (all)
    //      Data set via setElementRows/appendElementRows/clearElementRows.
    //      Selection and doubleClickActionID work the same as Form 1.
    //
    //    Performance: Rows are identified by stable indices in ForEach, optimizing SwiftUI diffing for
    //    large lists (e.g., 10,000 items). When row styling properties (listRowBackground, listRowSeparator,
    //    listRowInsets) are set, rows are wrapped with AnyView to support modifier chaining. Without row
    //    styling, this is a no-op wrapper with negligible overhead. Image creation uses SwiftUI.Image
    //    extension, aligned with Image.swift. Ensure state updates are targeted to minimize re-renders.

//  Observable state:
//    value ([String])                   Selected item as a one-element string array (or empty when nothing selected).
//                                       Access via getElementValue / setElementValue.
//    states["content"]  [[String]]      All list items; each inner array holds the item string and any optional
//                                       hidden-column data. Access via getElementRows / setElementRows /
//                                       appendElementRows / clearElementRows.
```
