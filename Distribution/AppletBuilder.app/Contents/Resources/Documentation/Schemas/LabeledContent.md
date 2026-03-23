# ActionUI.LabeledContent

JSON schema and usage documentation for `LabeledContent`.

```jsonc
// Sources/Views/LabeledContent.swift
// JSON specification for ActionUI.LabeledContent:
 {
   "type": "LabeledContent",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Username"  // Required: String for the label displayed before the content
   },
   "children": [
     { "type": "TextField", "id": 2, "properties": { "prompt": "Enter username" } }
   ]
   // Note: LabeledContent pairs a title label with one or more child views. It renders consistently
   // across all container contexts (Form, VStack, etc.), making labels visible where SwiftUI's built-in
   // view labels (e.g., TextField's title) would otherwise be hidden. Baseline View properties (padding,
   // hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and
   // additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers.
 }
```
