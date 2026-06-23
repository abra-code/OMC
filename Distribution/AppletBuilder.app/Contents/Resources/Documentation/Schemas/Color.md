# ActionUI.Color

JSON schema and usage documentation for `Color`.

```jsonc
// Sources/Views/Color.swift
// JSON specification for ActionUI.Color:
{
  "type": "Color",
  "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
  "properties": {
    "color": "blue"     // Required: a color string - a named color ("red", "primary"/"secondary"),
                        //           a hex string ("#RRGGBB" / "#RRGGBBAA"), or "<color>.opacity(<fraction>)".
                        //           Resolved via ColorHelper.resolveColor (named / semantic / hex / opacity).
  }
  // SwiftUI's `Color` is itself a View: a greedy block that fills the proposed space - the canonical way
  // to use a solid color as a view (a colored divider, a tinted background block), simpler than a
  // Rectangle().fill(). Give it a `frame` to size it (e.g. height 2 for a divider).
  // Baseline View properties (frame, padding, opacity, cornerRadius, hidden, etc.) are inherited and
  // applied via ActionUIRegistry.shared.applyViewModifiers.
}
```

## Value

The displayed color defaults to the `color` property and can be overridden at runtime (like `Image`'s value overriding its `systemName`/`assetName`) - the block re-renders:

- `setElementValue(viewID:value:)` with a `Color`.
- `setElementValueFromString(viewID:value:)` with a color string ("red", "#FF0000", "blue.opacity(0.3)") - parsed via `ColorHelper.resolveColor`.

`getElementValue(viewID:)` returns the runtime override, or `nil` when the `color` property is still in effect.
