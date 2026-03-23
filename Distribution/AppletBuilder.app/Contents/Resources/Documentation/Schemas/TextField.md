# ActionUI.TextField

JSON schema and usage documentation for `TextField`.

```jsonc
// Sources/Views/TextField.swift
// JSON specification for ActionUI.TextField:
 {
   "type": "TextField",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Username",            // Optional: String label for the field, defaults to "" (shown in Form/LabeledContent contexts)
     "text": "Hello",                // Optional: String initial value for the field, defaults to ""
     "prompt": "Enter text",         // Optional: String prompt (placeholder) shown inside the field when empty, defaults to nil
     "axis": "vertical",            // Optional: "vertical" for multi-line text field that grows with content. Defaults to horizontal (single-line).
                                     //   Use with lineLimit to control height. Preferred over TextEditor when placeholder text is needed.
     "lineLimit": 5,                 // Optional: Int (exact) or {"min": N} or {"min": N, "max": N} for range. Controls visible line count.
                                     //   Especially useful with axis "vertical" (e.g., lineLimit {"min": 3} for minimum 3 lines).
     "format": "decimal",            // Optional: "integer", "decimal", "percent", "currency". When set, uses SwiftUI value:format: constructor. Value is stored as String internally
     "currencyCode": "USD",          // Optional: ISO 4217 currency code, defaults to "USD". Only used with format "currency"
     "fractionLength": {"min": 0, "max": 2}, // Optional: Int (exact) or {"min": N, "max": N} (range). Controls decimal places for decimal/percent/currency
     "value": 9.99,                  // Optional: Initial numeric value (Int, Double, or String). Used instead of "text" when format is set. Defaults to 0
     "textContentType": "username",  // Optional: String for content type (e.g., "username", "password"), defaults to nil, ignored on macOS
     "actionID": "text.submit",      // Optional: String for action triggered on submit (e.g., Return key, inherited from View)
                                     //   On macOS, actionID is also triggered when the field loses focus (tab away, click elsewhere),
                                     //   matching classic AppKit text field behavior where ending editing commits the value.
     "valueChangeActionID": "text.valueChanged" // Optional: String for action triggered on any value change (user or programmatic, inherited from View)
   }
 }

// Multi-line TextField example (preferred over TextEditor when placeholder text is needed):
// {
//   "type": "TextField",
//   "id": 3,
//   "properties": {
//     "prompt": "Enter description...",
//     "axis": "vertical",
//     "lineLimit": {"min": 3, "max": 10}
//   }
// }

// Formatted numeric TextField example (value stored as String, converted internally):
// {
//   "type": "TextField",
//   "id": 2,
//   "properties": {
//     "title": "Price",
//     "format": "currency",          // Optional: "integer", "decimal", "percent", "currency". When set, uses SwiftUI value:format: constructor
//     "currencyCode": "USD",         // Optional: ISO 4217 currency code, defaults to "USD". Only used with format "currency"
//     "fractionLength": {"min": 0, "max": 2}, // Optional: Int (exact) or {"min": N, "max": N} (range). Controls decimal places for decimal/percent/currency
//     "value": 9.99                  // Optional: Initial numeric value (Int, Double, or String). Used instead of "text" when format is set. Defaults to 0
//   }
// }

// Note: The TextField view triggers an action via 'actionID' when the user submits input (e.g., Return key or "Done" on iOS). On macOS, actionID is also triggered on focus loss (tab, click away) to match classic AppKit behavior. valueChangeActionID is triggered continously on each change via the binding's set closure.
// Supported values for "textContentType": "name", "namePrefix", "givenName", "middleName", "familyName", "nameSuffix", "nickname", "jobTitle", "organizationName", "location", "fullStreetAddress", "streetAddressLine1", "streetAddressLine2", "addressCity", "addressState", "addressCityAndState", "sublocality", "countryName", "postalCode", "telephoneNumber", "emailAddress", "url", "creditCardNumber", "creditCardSecurityCode", "creditCardName", "creditCardExpiration", "creditCardType", "username", "password", "newPassword", "oneTimeCode", "shipmentTrackingNumber", "flightNumber", "dateTime", "birthdate", "birthdateDay", "birthdateMonth", "birthdateYear", "paymentMethod" (ignored on macOS). Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties). On macOS, the default text field style (likely rounded) is used.
// Note: actionID is triggered via onSubmit for user-initiated submits (e.g., Return key).  Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, disabled, etc.) are inherited and applied via ActionUIRegistry.shared.applyModifiers. On macOS, the default text field style (likely rounded) is used.
// Observable state:
//   value (String)   Current text entered in the field (via getElementValue / setElementValue).
```
