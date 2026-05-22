# ActionUI.ControlGroup

JSON schema and usage documentation for `ControlGroup`.

```jsonc
// Sources/Views/ControlGroup.swift
// Sample JSON for ControlGroup:
{
  "type": "ControlGroup",
  "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
  "properties": {
    "title": "Options"  // Optional: String for the control group title; defaults to nil
  },
  "children": [
    { "type": "Button", "properties": { "title": "Option 1", "actionID": "option1" } }
  ]
  // Note: These properties are specific to ControlGroup. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
}
```
