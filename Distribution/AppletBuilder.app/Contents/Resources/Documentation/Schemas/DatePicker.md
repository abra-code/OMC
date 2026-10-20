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
     "displayedComponents": "date", // Optional: "date" (default), "hourAndMinute" (time picker), "dateAndTime" (date+time); defaults to "date"
     "range": { "start": "2023-01-01", "end": "2025-12-31" }, // Optional: Dictionary with start/end dates (ISO 8601 strings)
     "selectedDate": "2024-07-16" // Optional: Initial selected value. Accepts "YYYY-MM-DD", "HH:mm", or a full ISO datetime
   }
   // Note: These properties are specific to DatePicker. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
// Observable state:
//   value (String)   Selected value as an ISO 8601 string (via getElementValue / setElementValue).
//                    "date" mode emits/accepts a bare date "YYYY-MM-DD" (backward compatible).
//                    "hourAndMinute" and "dateAndTime" emit a full ISO datetime "YYYY-MM-DDTHH:mm:ss"
//                    ("hourAndMinute" uses today's date so a host can read the HH:mm).
//                    Write an ISO 8601 date/datetime string to set the value programmatically.
//                    What an input string means (selectedDate, range, and values written by a host):
//                      "YYYY-MM-DD"                          a calendar day
//                      "YYYY-MM-DDTHH:mm[:ss]"               wall-clock time in the device's time zone
//                      "YYYY-MM-DDTHH:mm[:ss[.fff]]" + "Z", "+hh:mm", "+hhmm" or "+hh"
//                                                            an instant; the zone is honored and the
//                                                            picker shows it in the device's time zone
//                                                            (a "date" picker shows that instant's local day)
//                      "HH:mm[:ss]"                          that wall-clock time today
//                    Emitted values never carry a zone: they are the local day or local wall-clock time.
//                    To give a calendar day, pass "YYYY-MM-DD", not a UTC midnight such as "...T00:00:00Z".
```
