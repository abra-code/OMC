# ActionUI background (subview)

JSON schema and usage documentation for the `background` subview modifier (available on any view).

> **Note**: The `"background"` root key (a child element) is distinct from the `"background"` property (a color string).
> Both may be used together — the property sets a flat color; the subview places a shaped view behind the content.

```jsonc
// Sources/Views/View.swift
// JSON specification for the background subview modifier:
{
  "type": "AnyView",
  "properties": {
    "backgroundAlignment": "center"  // Optional: Alignment for the background subview.
                                     //   "center" (default), "leading", "trailing", "top", "bottom",
                                     //   "topLeading", "topTrailing", "bottomLeading", "bottomTrailing"
  },
  "background": {    // Optional: A single child view placed behind this view via .background(alignment:content:).
                     //   Applied after the "background" color property (if set), before frame.
                     //   Use for shape-backed labels, card backgrounds, or stroked outlines.
    "type": "RoundedRectangle",
    "properties": { "cornerRadius": 12.0, "fill": "blue" }
  }
}

// Common patterns:
//
// Capsule-backed label (colored tag):
// { "type": "Text", "properties": { "text": "New", "foregroundStyle": "white", "padding": { "leading": 10, "trailing": 10, "top": 5, "bottom": 5 } },
//   "background": { "type": "Capsule", "properties": { "fill": "blue" } } }
//
// Rounded button background:
// { "type": "Text", "properties": { "text": "Save", "foregroundStyle": "white", "padding": { "leading": 16, "trailing": 16, "top": 10, "bottom": 10 } },
//   "background": { "type": "RoundedRectangle", "properties": { "cornerRadius": 10, "fill": "blue" } } }
//
// Stroked outline:
// { "type": "Text", "properties": { "text": "Outlined", "foregroundStyle": "tint", "padding": 10 },
//   "background": { "type": "RoundedRectangle", "properties": { "cornerRadius": 8, "stroke": "tint", "strokeLineWidth": 1.5 } } }
//
// Card background:
// { "type": "VStack", "properties": { "alignment": "leading", "padding": { "leading": 16, "trailing": 16, "top": 14, "bottom": 14 } },
//   "children": [ ... ],
//   "background": { "type": "RoundedRectangle", "properties": { "cornerRadius": 12, "fill": "fill" } } }
```
