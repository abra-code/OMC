# ActionUI.Tab

JSON schema and usage documentation for `Tab`.

```jsonc
// Sources/Views/Tab.swift
// Sample JSON for Tab:
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
}
```

> Tab is not meant to be instantiated outside of TabView definition. It is only used as a distinct element to take advantage of the existing decoding infrastructure for the `children` array in TabView.
