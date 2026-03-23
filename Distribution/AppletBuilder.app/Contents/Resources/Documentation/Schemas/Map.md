# ActionUI.Map

JSON schema and usage documentation for `Map`.

```jsonc
// Sources/Views/Map.swift
// JSON specification for ActionUI.Map:
 {
   "type": "Map",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "coordinate": { "latitude": 37.33233141, "longitude": -122.0312186 }, // Optional: Dictionary with latitude/longitude, defaults to nil
     "showsUserLocation": true, // Optional: Boolean for user location, defaults to false
     "interactionModes": ["pan", "zoom"], // Optional: Array of "pan", "zoom", "rotate", defaults to ["pan", "zoom", "rotate"]
     "annotations": [ // Optional: Array of annotations
       {
         "coordinate": { "latitude": 37.332, "longitude": -122.031 },
         "title": String?, // Optional
         "subtitle": String? // Optional
       }
     ]
   }
   // Note: These properties are specific to Map. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
   // Design decision: Uses modern Map initializer with MapCameraPosition and MapContentBuilder (macOS 14.0+, iOS 17.0+). Annotations use Annotation for title/subtitle support.
 }
// Observable state:
//   value (String)   Current map center as a JSON coordinate string, e.g.
//                    "{\"latitude\":37.33233141,\"longitude\":-122.0312186}"
//                    (via getElementValue / setElementValue). Write a JSON coordinate string to
//                    re-center the map programmatically.
```
