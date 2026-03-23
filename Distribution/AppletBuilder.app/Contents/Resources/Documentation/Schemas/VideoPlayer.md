# ActionUI.VideoPlayer

JSON schema and usage documentation for `VideoPlayer`.

```jsonc
// Sources/Views/VideoPlayer.swift
// JSON specification for ActionUI.VideoPlayer:
 {
   "type": "VideoPlayer",
   "id": 1,
   "properties": {
     "url": "https://example.com/video.mp4", // Optional: URL string, returns EmptyView if nil or invalid
     "autoplay": true    // Optional: Boolean for autoplay, ignored if nil
   }
   // Note: These properties are specific to VideoPlayer. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
// Observable state:
//   value (String)   URL string of the currently loaded video (via getElementValue / setElementValue).
//                    Write a new URL string to swap the video source at runtime.
```
