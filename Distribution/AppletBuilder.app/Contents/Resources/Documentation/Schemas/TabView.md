# ActionUI.TabView

JSON schema and usage documentation for `TabView`.

```jsonc
// Sources/Views/TabView.swift
// JSON specification for ActionUI.TabView:
 {
   "type": "TabView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "selection": 0,     // Optional: Integer for selected tab index (0-based), defaults to 0
     "style": "automatic" // Optional: "automatic" (default), "tabBarOnly", "sidebarAdaptable" (iOS 18+/macOS 15+), "page" (iOS/tvOS/watchOS/visionOS only), "verticalPage" (watchOS only), "grouped" (macOS only)
   },
   "children": [         // Required: Array of tab configurations with content
     {
       "type": "Tab",
       "properties": {          // Tab configuration (not a view type, just tab metadata)
         "title": "Home",        // Required: String for tab title
         "systemImage": "house", // Optional: String for SF Symbol name
         "assetImage": "myTab",  // Optional: String for asset image name. One of systemImage or assetImage must be provided
         "badge": 5              // Optional: Integer or String for badge display
       },
       "content": {      // Required: Single child view for tab content
         "type": "VStack",
         "properties": { "spacing": 10 },
         "children": [
           { "type": "Text", "properties": { "text": "Home Content" } }
         ]
       }
     },
     {
       "type": "Tab",
       "properties": {
         "title": "Settings",
         "systemImage": "gear",
         "badge": "!"
       },
       "content": {
         "type": "Text",
         "properties": { "text": "Settings Content" }
       }
     }
   ]
   // Note: These properties are specific to TabView. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
   // Note: Each child in "children" is a dictionary with "properties" (tab configuration) and "content" (the actual ActionUIView to display). Tabs are identified by their index (0-based) in the children array.
   // Note: TabView supports "actionID" to trigger actions when selection changes via user interaction and passes selected tab index as context
   // Note: The "style" property controls the tab view style:
   //   "automatic" — default platform behavior (all platforms)
   //   "tabBarOnly" — always show tab bar (iOS 18+/macOS 15+)
   //   "sidebarAdaptable" — adaptive sidebar on iPad (iOS 18+/macOS 15+)
   //   "page" — horizontal scrolling pages (iOS/tvOS/watchOS/visionOS only, not macOS)
   //   "verticalPage" — vertical scrolling pages (watchOS only)
   //   "grouped" — grouped tab style (macOS only)
   // Platform compatibility: Uses native SwiftUI.Tab on iOS 18+/macOS 15+, falls back to .tabItem modifier on iOS 17.6/macOS 14.6 for backward compatibility.
 }
// Observable state:
//   value (Int)   Index of the currently selected tab (0-based) (via getElementValue / setElementValue).
```
