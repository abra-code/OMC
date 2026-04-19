# ActionUI.Rectangle

JSON schema and usage documentation for `Rectangle`.

```jsonc
// Sources/Views/Rectangle.swift
// JSON specification for ActionUI.Rectangle:
{
  "type": "Rectangle",
  "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
  "properties": {
    "fill": "blue",         // Optional: Fill color/style string (e.g. "red", "tint", "primary", "#FF0000").
                            //           Resolved via ColorHelper.resolveShapeStyle — supports named colors
                            //           and semantic styles. Mutually exclusive with stroke; fill takes priority.
    "stroke": "red",        // Optional: Stroke color/style string. Used when fill is absent.
    "strokeLineWidth": 2.0  // Optional: CGFloat stroke width (default 1.0). Only applies when stroke is set.
  }
  // Note: These properties are specific to Rectangle. Baseline View properties (frame, padding, foregroundStyle,
  // background, opacity, cornerRadius, hidden, disabled, etc.) are inherited and applied via
  // ActionUIRegistry.shared.applyViewModifiers. foregroundStyle acts as fill color on bare shapes.
}
```
