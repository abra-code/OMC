# ActionUI.Image

JSON schema and usage documentation for `Image`.

```jsonc
// Sources/Views/Image.swift
// JSON specification for ActionUI.Image:
 {
   "type": "Image",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "systemName": "star.fill",  // Optional: String for SF Symbol
     "assetName": "customImage",      // Optional: String for asset catalog image name
     "resourceName": "yourImage.png",      // Optional: String for bundle resource image name with extension
     "filePath": "/path/to/image.jpg", // Optional: String for local file path
     "resizable": true,          // Optional: Boolean to make image resizable, defaults to true if scaleMode is specified
     "scaleMode": "fit",         // Optional: String ("fit" or "fill") for scaling mode, defaults to "fit"
     "imageScale": "large"       // Optional: String ("small", "medium", "large") for image scale, applies to SF Symbols, no default
   }
   // Note: These properties are specific to Image. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled, accessibilityLabel, accessibilityHint, accessibilityHidden, accessibilityIdentifier, shadow) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
   // Note: To enable scrolling, wrap Image in a ScrollView manually, e.g.:
   // {
   //   "type": "ScrollView",
   //   "children": [
   //     {
   //       "type": "Image",
   //       "properties": { ... }
   //     }
   //   ]
   // }
 }
```
