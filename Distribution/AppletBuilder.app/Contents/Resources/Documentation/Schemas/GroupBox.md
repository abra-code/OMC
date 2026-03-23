# ActionUI.GroupBox

JSON schema and usage documentation for `GroupBox`.

```jsonc
// Sources/Views/GroupBox.swift
// JSON specification for ActionUI.GroupBox:
 {
   "type": "GroupBox",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Settings"  // Optional: String for the group box title; defaults to nil
   },
   "children": [
     { "type": "Text", "properties": { "text": "Content" } }
   ]
   // Note: These properties are specific to GroupBox. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
```
