# ActionUI.Gauge

JSON schema and usage documentation for `Gauge`.

```jsonc
// Sources/Views/Gauge.swift
// JSON specification for ActionUI.Gauge:
 {
   "type": "Gauge",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "value": 0.75,       // Optional: Value (Double), defaults to 0.0
     "title": "Progress", // Optional: String for title, defaults to nil
     "style": "accessoryCircular", // Optional: "accessoryCircular", "accessoryCircularCapacity", "accessoryLinear", "accessoryLinearCapacity" (iOS/macOS/visionOS); defaults to "accessoryCircular"
     "range": { "min": 0.0, "max": 100.0 } // Optional: Dictionary with min/max values, defaults to 0.0 to 1.0
   }
   // Note: These properties are specific to Gauge. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
// Observable state:
//   value (Double)   Current gauge value within the declared range (via getElementValue / setElementValue).
```
