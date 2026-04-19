# ActionUI.Circle

JSON schema and usage documentation for `Circle`.

```jsonc
// Sources/Views/Circle.swift
// JSON specification for ActionUI.Circle:
{
  "type": "Circle",
  "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
  "properties": {
    "fill": "green",        // Optional: Fill color/style string (e.g. "red", "tint", "primary", "#FF0000").
                            //           Resolved via ColorHelper.resolveShapeStyle. Mutually exclusive with
                            //           stroke; fill takes priority.
    "stroke": "orange",     // Optional: Stroke color/style string. Used when fill is absent.
    "strokeLineWidth": 4.0  // Optional: CGFloat stroke width (default 1.0). Only applies when stroke is set.
  }
  // Note: These properties are specific to Circle. Baseline View properties (frame, padding, foregroundStyle,
  // background, opacity, hidden, disabled, etc.) are inherited and applied via
  // ActionUIRegistry.shared.applyViewModifiers. Use frame to constrain the circle's size.
}
```
