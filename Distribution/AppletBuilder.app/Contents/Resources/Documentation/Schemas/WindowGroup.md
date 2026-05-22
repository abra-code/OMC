# ActionUI.WindowGroup

JSON schema and usage documentation for `WindowGroup`.

```jsonc
// Sources/WindowGroup.swift
// Constructs a SwiftUI.WindowGroup<AnyView> from an ActionUIElementBase.
//
// Expected JSON properties:
{
  "type": "WindowGroup",
  "id": 1,                       // Unique identifier
  "properties": {
    "title": "Untitled",         // Optional: Non-empty string for the window title, defaults to "Untitled" if not provided
    "windowGroupID": "Welcome"   // Optional: Non-empty string for the WindowGroup id — must be unique, used to identify the window content template, defaults to "title" if not provided
  },
  "content": {
    // Required: A single view element (e.g., VStack, Text)
    "type": "VStack",
    "id": 2,
    "properties": {
      "alignment": "center",
      "spacing": 10.0
    },
    "children": [
      { "type": "Text", "id": 3, "properties": { "text": "Welcome to ActionUI" } }
    ]
  },
  "commands": [
    // Optional: Array of command elements, limited to 10 root-level commands due to SwiftUI CommandsBuilder restrictions
    {
      "type": "CommandMenu",
      "id": 4,
      "properties": {
        "name": "Test"            // Required: Non-empty string for the menu title
      },
      "children": [
        {
          "type": "Button",
          "id": 5,
          "properties": {
            "title": "Custom Action",
            "actionID": "custom.action",
            "keyboardShortcut": {
              "key": "n",
              "modifiers": ["command"]
            }
          }
        },
        { "type": "Divider", "id": 6, "properties": {} }
      ]
    },
    {
      "type": "CommandGroup",
      "id": 7,
      "properties": {
        "placement": "replacing", // Required: One of "replacing", "before", "after"
        "placementTarget": "newItem"
        // Required placementTarget values: "appInfo", "appSettings", "systemServices",
        // "appVisibility", "appTermination", "newItem", "saveItem", "importExport",
        // "printItem", "undoRedo", "pasteboard", "textEditing", "textFormatting",
        // "toolbar", "sidebar", "windowSize", "windowList", "singleWindowList",
        // "windowArrangement", "help"
      },
      "children": [
        {
          "type": "Button",
          "id": 8,
          "properties": {
            "title": "Custom Action",
            "actionID": "custom.action",
            "keyboardShortcut": { "key": "n", "modifiers": ["command"] }
          }
        }
      ]
    }
  ]
}
```

> WindowGroup is a scene-level element — the root of an ActionUI window description. It is not a regular view; it cannot appear as a child of another element. Use it as the top-level type in a window template file. The `commands` array is limited to 10 root-level entries due to SwiftUI's `CommandsBuilder` restrictions; additional entries are ignored with a warning logged.
