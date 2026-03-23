# ActionUI.AsyncImage

JSON schema and usage documentation for `AsyncImage`.

```jsonc
// Sources/Views/AsyncImage.swift
// JSON specification for ActionUI.AsyncImage:
 {
   "type": "AsyncImage",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "url": "https://example.com/image.jpg", // Required: String for web or local file URL, returns placeholder if nil or invalid
     "placeholder": "photo",                 // Optional: String for SF Symbol or asset name, defaults to "photo" in buildView
     "resizable": true,                     // Optional: Boolean to make image resizable, defaults to true in buildView
     "contentMode": "fit"                   // Optional: "fit" or "fill" for scaling mode, defaults to "fit" in buildView
   }
   // Note: These properties are specific to AsyncImage. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
   // Note: Invalid URLs (e.g., "invalid-url") are allowed and will construct AsyncImage, which may fail to download but should not crash.
 }
```
