# ActionUI.Slider

JSON schema and usage documentation for `Slider`.

```jsonc
// Sources/Views/Slider.swift
// JSON specification for ActionUI.Slider:
 {
   "type": "Slider",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "value": 50.0,       // Optional: Initial value (Double), defaults to 0.0
     "range": { "min": 0.0, "max": 100.0 }, // Optional: Dictionary with min/max values, defaults to 0.0 to 1.0. "range" becomes required if you specify "step"
     "step": 1.0          // Optional: Step increment (Double), defaults to continuous sliding if not present
   }
   // Note: These properties are specific to Slider. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
// Observable state:
//   value (Double)   Current slider position within the declared range (via getElementValue / setElementValue).
```
