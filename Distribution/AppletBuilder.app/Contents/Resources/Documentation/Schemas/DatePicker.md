# ActionUI.DatePicker

JSON schema and usage documentation for `DatePicker`.

```jsonc
// Sources/Views/DatePicker.swift
// JSON specification for ActionUI.DatePicker:
 {
   "type": "DatePicker",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Select Date", // Optional: String for title, defaults to "Date"
     "displayStyle": "automatic", // Optional: "automatic" (iOS/macOS/visionOS), "compact" (iOS/macOS/visionOS), "graphical" (iOS/macOS/visionOS), "stepperField" (macOS only), "field" (macOS only); defaults to "automatic"
     "range": { "start": "2023-01-01", "end": "2025-12-31" }, // Optional: Dictionary with start/end dates (ISO 8601 strings)
     "selectedDate": "2024-07-16" // Optional: Initial selected date (ISO 8601 string)
   }
   // Note: These properties are specific to DatePicker. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
// Observable state:
//   value (String)   Selected date as an ISO 8601 string (e.g., "2024-07-16T00:00:00Z") (via getElementValue / setElementValue).
//                    Write an ISO 8601 date string to set the selected date programmatically.
```
