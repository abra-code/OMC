# ActionUI.CommandMenu

JSON schema and usage documentation for `CommandMenu`.

```jsonc
// Sources/Common/CommandMenu.swift
// JSON specification for ActionUI.CommandMenu:
// Constructs a SwiftUI.CommandMenu from an ActionUIElementBase.
// Adds a new top-level menu to the menu bar (inserted before Window and Help).
 {
   "type": "CommandMenu",
   "id": 8,              // Required: Unique integer identifier
   "properties": {
     "name": "Test"      // Required: Non-empty string for the menu title
   },
   "children": [
     // Array of child elements (Button, Divider)
     {
       "type": "Button",
       "id": 9,
       "properties": {
         "title": "Test Something",           // Required: Button title
         "actionID": "test.something",        // Optional: Identifier for action dispatching
         "keyboardShortcut": {                // Optional
           "key": "t",                        // Required: Single character or special key (e.g., "return")
           "modifiers": ["command", "shift"]  // Optional: Array of modifiers (e.g., ["command", "shift"])
         }
       }
     },
     {
       "type": "Divider",
       "id": 10
       // properties: Optional, typically empty
     }
   ]
 }
```
