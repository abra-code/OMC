# ActionUI.CommandGroup

JSON schema and usage documentation for `CommandGroup`.

```jsonc
// Sources/Common/CommandGroup.swift
// JSON specification for ActionUI.CommandGroup:
// Constructs a SwiftUI.CommandGroup from an ActionUIElementBase.
// Inserts or replaces items in an existing default menu using placement + placementTarget.
 {
   "type": "CommandGroup",
   "id": 4,              // Required: Unique integer identifier
   "properties": {
     "placement": "replacing",       // Optional: One of "replacing", "before", "after". Defaults to "after" if missing or invalid
     "placementTarget": "newItem"    // Optional: One of "appInfo", "appSettings", "systemServices", "appVisibility", "appTermination", "newItem", "saveItem", "importExport", "printItem", "undoRedo", "pasteboard", "textEditing", "textFormatting", "toolbar", "sidebar", "windowSize", "windowList", "singleWindowList", "windowArrangement", "help". Defaults to "help" if missing or invalid
   },
   "children": [
     // Array of child elements (Button, Divider)
     {
       "type": "Button",
       "id": 5,
       "properties": {
         "title": "Custom Action",            // Required: Button title
         "actionID": "custom.action",         // Optional: Identifier for action dispatching
         "keyboardShortcut": {                // Optional
           "key": "n",                        // Required: Single character or special key (e.g., "return")
           "modifiers": ["command"]           // Optional: Array of modifiers (e.g., ["command", "shift"])
         }
       }
     }
   ]
 }
```
