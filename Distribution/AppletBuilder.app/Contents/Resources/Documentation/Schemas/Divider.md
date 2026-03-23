# ActionUI.Divider

JSON schema and usage documentation for `Divider`.

```jsonc
// Sources/Views/Divider.swift
// JSON specification for ActionUI.Divider:
 {
   "type": "Divider",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
   }
   // Note: These properties are specific to Divider. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
```
