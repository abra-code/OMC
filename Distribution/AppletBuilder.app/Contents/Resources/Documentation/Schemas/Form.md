# ActionUI.Form

JSON schema and usage documentation for `Form`.

```jsonc
// Sources/Views/Form.swift
// JSON specification for ActionUI.Form:
 {
   "type": "Form",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
   },
   "children": [
      { "type": "Text", "properties": { "text": "Field 1" } }
   ] // Required: Array of child views
   // Note: These properties are specific to Form. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
```
