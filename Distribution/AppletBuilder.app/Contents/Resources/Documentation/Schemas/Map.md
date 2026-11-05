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
   // Note: These properties are specific to Map. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
   // Design decision: Uses modern Map initializer with MapCameraPosition and MapContentBuilder. Each annotation is a red pin standing on its coordinate (an Annotation whose content is the pin), with its title and subtitle drawn under it as MapKit's label.
 }
// Observable state:
//   value (String)   Current map center as a JSON coordinate string, e.g.
//                    "{\"latitude\":37.33233141,\"longitude\":-122.0312186}"
//                    (via getElementValue / setElementValue). Write a JSON coordinate string to
//                    re-center the map programmatically.
```

### Host differences

- **Linux** shows OpenStreetMap's standard tiles through libshumate (package `libshumate-1.0-1`, loaded when a Map is first made; without it the Map shows a placeholder naming the package), as Android's map-osm module does, with the attribution OpenStreetMap requires, a scale, zoom buttons and a compass. OpenStreetMap's tile servers are for light use: an app that shows maps to many people should not rely on them. Tile requests name the application (its ID, else its program name) and ActionUI's version, as their usage policy asks, and downloaded tiles are kept in the user's cache folder. The map opens framed as on Apple, a region 0.1 degrees of latitude by 0.1 of longitude around the value, all of it in view. Setting the value moves the center and keeps the zoom. When the map stops moving, the value follows its center and `valueChangeActionID` fires if the center changed; `actionID` fires after every move, one a host's value made included, but not when the map opens. Without `"pan"` in `interactionModes` dragging and the arrow keys do nothing; without `"zoom"` the scroll wheel, pinching and double-clicking do nothing and the zoom buttons are hidden; `"rotate"` works only together with `"zoom"`. Each annotation is a red pin with its tip on the coordinate and its title (bold) and subtitle centered under it, in dark text with a white halo, as the tiles stay light in dark mode. A drag that starts on a pin moves the map. With `showsUserLocation`, the user's location is libshumate's dot, in the desktop's accent color, from the desktop's location portal while the map is on screen; like Apple's, it never moves the map, sets the value or fires an action. It needs the desktop's location service: GeoClue, and on GNOME Location Services turned on in Settings (off by default). Without it there is no dot. Location Services turned off while the map is on screen leaves the dot where it was.
