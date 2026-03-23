# ActionUI.HStack

JSON schema and usage documentation for `HStack`.

```jsonc
// Sources/Views/HStack.swift
// JSON specification for ActionUI.HStack:
 {
   "type": "HStack",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "spacing": 10.0      // Optional: Double for spacing between elements
   },
   "children": [
     { "type": "Text", "properties": { "text": "Item 1" } },
     { "type": "Text", "properties": { "text": "Item 2" } }
   ]
   // Note: The spacing property is specific to HStack. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
```
