# ActionUI.Stepper

JSON schema and usage documentation for `Stepper`.

```jsonc
// Sources/Views/Stepper.swift
// JSON specification for ActionUI.Stepper:
 {
   "type": "Stepper",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "value": 5.0,        // Optional: Initial value (Double), defaults to 0.0
     "range": { "min": 0.0, "max": 10.0 }, // Optional: Dictionary with min/max values; no range clamping if omitted
     "step": 1.0,         // Optional: Step increment (Double), defaults to 1.0
     "label": "Quantity", // Optional: Static string label; ignored when labelFormat is set
     "labelFormat": "Quantity: %.0f", // Optional: printf-style format string embedding the current value.
                          // Use float specifiers (%g, %f, %.0f, %.1f, etc.) since the value is always a Double.
                          // Examples: "Count: %.0f" → "Count: 5", "Rating: %.1f" → "Rating: 2.5",
                          //           "Volume: %g%%" → "Volume: 50%"
                          // Takes precedence over "label" when both are present.
                          // The label is re-evaluated on every value change — no host code needed.
     "actionID": "stepper.changed" // Optional: String for action triggered on user-initiated value change
   }
   // Note: These properties are specific to Stepper. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
// Observable state:
//   value (Double)   Current stepper value (via getElementValue / setElementValue).
```
