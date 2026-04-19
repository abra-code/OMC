# ActionUI.Capsule

JSON schema and usage documentation for `Capsule`.

```jsonc
// Sources/Views/Capsule.swift
// JSON specification for ActionUI.Capsule:
{
  "type": "Capsule",
  "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
  "properties": {
    "style": "circular",    // Optional: "circular" (default) or "continuous" (squircle-style end caps).
    "fill": "green",        // Optional: Fill color/style string (e.g. "red", "tint", "primary", "#FF0000").
                            //           Mutually exclusive with stroke; fill takes priority.
    "stroke": "red",        // Optional: Stroke color/style string. Used when fill is absent.
    "strokeLineWidth": 2.0  // Optional: CGFloat stroke width (default 1.0). Only applies when stroke is set.
  }
  // Note: These properties are specific to Capsule. Baseline View properties (frame, padding, foregroundStyle,
  // background, opacity, hidden, disabled, etc.) are inherited and applied via
  // ActionUIRegistry.shared.applyViewModifiers. A Capsule fills its frame with fully-rounded ends;
  // use frame to set width/height.
}
```
