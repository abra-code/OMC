# ActionUI.SecureField

JSON schema and usage documentation for `SecureField`.

```jsonc
// Sources/Views/SecureField.swift
// JSON specification for ActionUI.SecureField:
 {
   "type": "SecureField",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Password",             // Optional: String label for the field, defaults to "" (shown in Form/LabeledContent contexts)
     "text": "",                       // Optional: String initial value, defaults to ""
     "prompt": "Enter password",       // Optional: String prompt (placeholder) shown inside the field when empty, defaults to nil
     "textContentType": "password",    // Optional: String for content type, must be one of: "password", "newPassword", "oneTimeCode"; defaults to nil, ignored on macOS
     "actionID": "secure.submit"       // Optional: String for action triggered on submit (e.g., Return key)
   }
   // Note: The SecureField view triggers an action via 'actionID' when the user submits input (e.g., Return key or "Done" on iOS). Supported values for "textContentType": "password", "newPassword", "oneTimeCode" (ignored on macOS). Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties). On macOS, the default text field style (likely rounded) is used.
 }
// Observable state:
//   value (String)   Current text entered in the secure field (via getElementValue / setElementValue).
```
