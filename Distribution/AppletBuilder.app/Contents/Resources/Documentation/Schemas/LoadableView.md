# ActionUI.LoadableView

JSON schema and usage documentation for `LoadableView`.

```jsonc
// Sources/Views/LoadableView.swift
// JSON specification for ActionUI.LoadableView:
 {
   "type": "LoadableView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "url": "https://example.com/view.json", // Optional: String URL to remote JSON or binary plist (http://, https://)
     "filePath": "/path/to/view.json",       // Optional: String absolute path to local JSON or binary plist
     "name": "HelloWorld.json",              // Optional: String name of JSON or binary plist resource in app bundle
     "viewDidLoadActionID": "view.loaded"    // Optional: String action triggered once after a new sub-view is loaded. Not re-triggered on SwiftUI body rebuilds for the same source.
   }
   // Note: Requires exactly one of "url", "filePath", or "name" to be valid. Loads JSON or binary plist, determined by .json or .plist extension, parses into ActionUIElementBase using ActionUIModel.loadDescription, and renders ActionUIView. Remote "url" loads asynchronously with ProgressView; local "filePath" or bundle "name" loads synchronously in init. Assumes unique IDs in loaded description to avoid conflicts with existing windowModels. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
   // Note: Invalid sources or unsupported extensions will result in error display. The source (url/filePath/name) is the designated value (valueType: String.self), settable via ActionUIModel.setElementValue, with heuristics: http:// or https:// for URL, file:// or / for filePath, else bundle name.
 }
// Observable state:
//   value (String)   Current source as a URL string, absolute file path, or bundle resource name
//                    (via getElementValue / setElementValue). Write a new value to reload the view
//                    from a different source; the heuristic (http(s):// means URL, file:// or / means filePath,
//                    else bundle name) applies at runtime.
```
