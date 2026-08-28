# ActionUI.ProgressView

JSON schema and usage documentation for `ProgressView`.

```jsonc
// Sources/Views/ProgressView.swift
// JSON specification for ActionUI.ProgressView:
 {
   "type": "ProgressView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "value": 0.5,       // Optional: Double for current progress (0.0 to total), defaults to nil for indeterminate
     "total": 1.0,       // Optional: Double for maximum progress, defaults to 1.0 if value is set
     "title": "Loading", // Optional: String for title, defaults to nil
     "progressViewStyle": "linear", // Optional: String ("automatic", "linear", "circular"), defaults to "automatic"
     "actionID": "progress.tap" // Optional: String for action triggered on tap
   }
   // Note: The ProgressView shows an indeterminate spinner if "value" or "total" is missing/invalid, or a determinate bar if both are valid. "progressViewStyle" overrides that: "linear" gives a bar in either state - which is the only way to ask for an indeterminate LINEAR bar - and "circular" gives a spinner or a circular gauge. On the Web port an indeterminate indicator is a linear bar natively and "circular" is not ported (it warns and stays linear). Platform-specific styling (e.g., .progressViewStyle(.circular) on iOS for indeterminate) is applied in applyModifiers. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
// Observable state (via getElementState / setElementState):
//   states["progress"] Double?   Current progress (0.0 – total). Overrides the initial JSON "value" property
//                                at runtime. Set to nil to revert to indeterminate.
```
