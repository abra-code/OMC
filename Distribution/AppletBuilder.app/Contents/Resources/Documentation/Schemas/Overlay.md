# ActionUI overlay

JSON schema and usage documentation for the `overlay` subview modifier (available on any view).

```jsonc
// Sources/Views/View.swift
// JSON specification for the overlay subview modifier:
{
  "type": "AnyView",
  "properties": {
    "overlayAlignment": "topTrailing"  // Optional: Alignment for the overlay subview.
                                       //   "center" (default), "leading", "trailing", "top", "bottom",
                                       //   "topLeading", "topTrailing", "bottomLeading", "bottomTrailing"
  },
  "overlay": {       // Optional: A single child view placed on top of this view via .overlay(alignment:content:).
                     //   Supports any ActionUI view type as content.
                     //   Applied after cornerRadius/border so the overlay sits on top of the final shaped view.
    "type": "Circle",
    "properties": { "fill": "red", "frame": { "width": 14.0, "height": 14.0 } }
  }
}

// Common patterns:
//
// Count badge:
// { "type": "Image", "properties": { "systemName": "envelope.fill", "overlayAlignment": "topTrailing" },
//   "overlay": {
//     "type": "ZStack", "properties": {},
//     "children": [
//       { "type": "Circle", "properties": { "fill": "red", "frame": { "width": 20, "height": 20 } } },
//       { "type": "Text", "properties": { "text": "3", "font": "caption2", "foregroundStyle": "white" } }
//     ]
//   } }
//
// Dot badge:
// { "type": "Image", "properties": { "systemName": "bell.fill", "overlayAlignment": "topTrailing" },
//   "overlay": { "type": "Circle", "properties": { "fill": "red", "frame": { "width": 12, "height": 12 } } } }
//
// Caption bar over image:
// { "type": "Rectangle", "properties": { "fill": "teal", "cornerRadius": 14, "frame": { "width": 260, "height": 150 }, "overlayAlignment": "bottom" },
//   "overlay": {
//     "type": "ZStack", "properties": { "alignment": "bottom" },
//     "children": [
//       { "type": "Rectangle", "properties": { "fill": "black", "opacity": 0.5, "frame": { "width": 260, "height": 50 } } },
//       { "type": "Text", "properties": { "text": "Caption", "foregroundStyle": "white" } }
//     ]
//   } }
```
