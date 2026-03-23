# ActionUI.Button

JSON schema and usage documentation for `Button`.

```jsonc
// Sources/Views/Button.swift
// JSON specification for ActionUI.Button:
{
  "type": "Button",
  "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
  "properties": {
    "title": "Click Me",    // Optional: String, defaults to empty in buildView
    "systemImage": "plus.circle", // Optional: SF Symbol name
    "assetImage": "Logo",   // Optional: name from Assets.xcassets
    "imageScale": "large",  // Optional: image scale: "small", "medium", "large". Defaults to "medium" if absent
    "buttonStyle": "plain", // Optional: Button style (e.g., "plain", "bordered", "borderedProminent"), defaults to "plain" in applyModifiers
    "role": "destructive"   // Optional: Button role (e.g., "destructive", "cancel")
  }
  // Note: These properties are specific to Button. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
}
```
