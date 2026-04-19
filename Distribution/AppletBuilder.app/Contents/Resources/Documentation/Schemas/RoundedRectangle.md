# ActionUI.RoundedRectangle

JSON schema and usage documentation for `RoundedRectangle`.

```jsonc
// Sources/Views/RoundedRectangle.swift
// JSON specification for ActionUI.RoundedRectangle:
{
  "type": "RoundedRectangle",
  "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
  "properties": {
    "cornerRadius": 12.0,        // Optional: CGFloat corner radius in points (default 0).
    "cornerStyle": "circular",   // Optional: "circular" (default) or "continuous" (squircle-style,
                                 //           matches iOS app icon rounding).
    "fill": "blue",              // Optional: Fill color/style string (e.g. "red", "tint", "primary", "#FF0000").
                                 //           Mutually exclusive with stroke; fill takes priority.
    "stroke": "red",             // Optional: Stroke color/style string. Used when fill is absent.
    "strokeLineWidth": 2.0       // Optional: CGFloat stroke width (default 1.0). Only applies when stroke is set.
  }
  // Note: These properties are specific to RoundedRectangle. Baseline View properties (frame, padding,
  // foregroundStyle, background, opacity, hidden, disabled, etc.) are inherited and applied via
  // ActionUIRegistry.shared.applyViewModifiers.
}
```
