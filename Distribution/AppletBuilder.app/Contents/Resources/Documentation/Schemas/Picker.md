# ActionUI.Picker

JSON schema and usage documentation for `Picker`.

```jsonc
// Sources/Views/Picker.swift
// JSON specification for ActionUI.Picker:
 {
   "type": "Picker",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Select Option",    // Optional: String, no default
     "options": [ "One",  "Two", "Three" ] // Required. Two supported formats:
       // 1. With simple array of strings we have titles only. Tags are automatically "1", "2", "3"... (1-based index as String)
       // 2. With array of dictionaries we have explicit control: [{"title": "Sure Thing", "tag": "yes"}, {"title": "Absolutely Not", "tag": "no"}]
       //    Optionally, dictionaries can include {"section": "Group Name"} entries to group items into named sections (works best with "menu" pickerStyle):
       //    [{"section": "Popular"}, {"title": "HTML", "tag": "html"}, {"section": "Other"}, {"title": "XML", "tag": "xml"}]
       //    Items following a section entry belong to that section until the next section entry.
       //    Items before any section entry are placed in an implicit ungrouped section.
       //    A {"divider": true} entry inserts a visual separator line (works best with "menu" pickerStyle).
     "pickerStyle": "menu",      // Optional: "menu" (iOS/macOS/visionOS), "segmented" (iOS/macOS/visionOS), "wheel" (iOS/visionOS only), "radioGroup" (macOS only); no default
     "horizontalRadioGroupLayout": false, // Optional: Bool, applies .horizontalRadioGroupLayout() when pickerStyle is "radioGroup" (macOS only); defaults to false
     "actionID": "picker.selection", // Optional: String for action triggered on user-initiated selection change (inherited from View)
   }
   // Note: actionID is triggered via onChange for user-initiated changes. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, disabled, etc.) are inherited and applied via ActionUIRegistry.shared.applyModifiers.
   // The selected tag is passed as `context` (Any?) to actionID handler.
 }
// Observable state:
//   value (String)   Tag of the currently selected option (via getElementValue / setElementValue).
//                    For simple string arrays the tag is the 1-based index as a String ("1", "2", …);
//                    for dictionary options it is the explicit "tag" value.
//                    For sectioned options the tag is the explicit "tag" value of the selected item.
```
