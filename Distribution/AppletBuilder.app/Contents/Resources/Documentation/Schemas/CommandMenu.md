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
     "name": "Test",     // Required: Non-empty string for the menu title
     "role:web": "account",                   // Optional, WEB ONLY: renders this menu as the shell's account button (top-right)
                                              //   instead of a menu-bar entry. "account" is the only recognized value; only the
                                              //   FIRST account menu is used, later ones warn and are ignored. Apple/Android ignore it.
     "systemImage:web": "person.crop.circle"  // Optional, WEB ONLY: SF Symbol for the account button's glyph, resolved through the
                                              //   SF-to-Material map. Read only when "role:web" is "account"; defaults to a person glyph.
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
