# ActionUI.ContentUnavailableView

JSON schema and usage documentation for `ContentUnavailableView`.

```jsonc
// Sources/Views/ContentUnavailableView.swift
// JSON specification for ActionUI.ContentUnavailableView:
 {
   "type": "ContentUnavailableView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "No Results",              // Required: String for the primary message
     "systemImage": "magnifyingglass",   // Optional: String for SF Symbol, defaults to nil (no image shown)
     "description": "Try a different search term." // Optional: String for secondary descriptive text, defaults to nil
   }
   // Note: ContentUnavailableView is the standard SwiftUI view for displaying empty states, missing data,
   // or no-results conditions.
   // Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled)
   // and additional View protocol modifiers are inherited and applied via
   // ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }

// Search variant (shows "No results for <query>" with magnifying glass icon):
// {
//   "type": "ContentUnavailableView",
//   "id": 2,
//   "properties": {
//     "search": true,      // Optional: Boolean. When true, uses the built-in search appearance.
//                           //   The search query text can be set via setElementValue to display "No results for <query>".
//                           //   When search is true, title/systemImage/description are ignored.
//     "query": "planets"   // Optional: String for the search query shown in the message. Can also be set at runtime via value.
//   }
// }
// Observable state:
//   value (String)   For search variant: the search query text. For standard variant: the title text.
//                    Can be set at runtime via setElementValue to update the displayed message.
```
