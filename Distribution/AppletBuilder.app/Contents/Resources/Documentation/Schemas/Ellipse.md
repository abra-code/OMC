# ActionUI.Ellipse

JSON schema and usage documentation for `Ellipse`.

```jsonc
// Sources/Views/Ellipse.swift
// JSON specification for ActionUI.Ellipse:
{
  "type": "Ellipse",
  "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
  "properties": {
    "fill": "orange",       // Optional: Fill color/style string (e.g. "red", "tint", "primary", "#FF0000").
                            //           Mutually exclusive with stroke; fill takes priority.
    "stroke": "purple",     // Optional: Stroke color/style string. Used when fill is absent.
    "strokeLineWidth": 3.0  // Optional: CGFloat stroke width (default 1.0). Only applies when stroke is set.
  }
  // Note: These properties are specific to Ellipse. Baseline View properties (frame, padding, foregroundStyle,
  // background, opacity, hidden, disabled, etc.) are inherited and applied via
  // ActionUIRegistry.shared.applyViewModifiers. Use frame with differing width/height to create a non-circular
  // ellipse; equal width/height produces a circle.
}
```
