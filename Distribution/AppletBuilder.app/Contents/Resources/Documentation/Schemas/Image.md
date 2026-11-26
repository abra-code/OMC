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
     "resourceName": "yourImage.png",  // Optional: String for a resource image name with extension (the host's resource folder, then the bundle; a name with "/" is not found)
     "filePath": "/path/to/image.jpg", // Optional: String, absolute local file path (a relative one resolves against the process's working directory)
     "resizable": true,          // Optional: Boolean, defaults to false. true scales the image to the space it is given (its frame); with no contentMode it stretches to fill it on both axes, not keeping its aspect ratio, as SwiftUI's .resizable() does. false: the image keeps its own size and a smaller frame does not shrink it
     "contentMode": "fit",       // Optional: String ("fit" or "fill"), no default. Keeps a resizable image's aspect ratio: "fit" shows the whole image inside the frame, "fill" covers the frame and may draw past it. No effect unless "resizable" is true, as SwiftUI's .aspectRatio(contentMode:) has none on an image that is not resizable
     "imageScale": "large"       // Optional: String ("small", "medium", "large") for image scale, applies to SF Symbols, no default
   }
   // Note: These properties are specific to Image. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled, accessibilityLabel, accessibilityHint, accessibilityHidden, accessibilityIdentifier, shadow) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
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
