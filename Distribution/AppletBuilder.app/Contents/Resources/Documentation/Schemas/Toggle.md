# ActionUI.Toggle

JSON schema and usage documentation for `Toggle`.

```jsonc
// Sources/Views/Toggle.swift
// JSON specification for ActionUI.Toggle:
 {
   "type": "Toggle",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "isOn": true,              // Optional: Boolean initial state, defaults to false
     "title": "Enable Feature", // Optional: String, defaults to "Toggle"
     "style": "switch",        // Optional: "switch" (iOS/macOS/visionOS), "checkbox" (macOS only), "button" (iOS/macOS/visionOS); defaults to "switch"
     "actionID": "toggle.changed", // Optional: String for action triggered when the user changes the value (context = the new Bool)
   }
   // Note: These properties are specific to Toggle. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
// Observable state:
//   value (Bool)   Current on/off state of the toggle (via getElementValue / setElementValue).
```

## In a data-driven template

Inside a `template` (a `List`, `VStack`, `HStack`, `LazyVStack`, ... that renders one instance per row of its rows), the row data is the source of truth for the Toggle. This is how a checkbox list is built:

```json
{
  "type": "List",
  "id": 600,
  "properties": { "actionID": "packs.selection.changed" },
  "template": {
    "type": "Toggle",
    "properties": {
      "style": "checkbox",
      "isOn": "$1",
      "title": "$2",
      "disabled": "$4",
      "actionID": "packs.toggled"
    }
  }
}
```

with rows such as `["true", "Xcode and Swift builds", "xcode", "false"]`.

- **`isOn` from the row.** A string is read after the `$N` substitution: `"true"` or `"1"` is on; `"false"`, `"0"` or an empty string is off; letter case does not matter. Any other text is off, and one warning is logged. A literal Boolean still works. `disabled` and `hidden` are read the same way, on any element in a template.
- **The row keeps the state.** When `isOn` is exactly one column reference (`"$1"`, `"$12"`), a user toggle writes `"true"` or `"false"` into that column of that row. `getElementRows` returns the new state and a redraw keeps it. Any other `isOn` (a literal, `"$0"`, text around a reference, or none) leaves the Toggle display-only: the click changes nothing and no action fires. The validators warn about it.
- **The action names the row.** A user toggle fires `actionID` with `viewID` = the container's id, `viewPartID` = the 0-based row index and `context` = the new Boolean, the same addressing as a `Button` in a template. It fires after the row is written, so a handler that reads the rows sees the new value.
- **Changes made by the host fire nothing.** `setElementRows`, `appendElementRows` and `clearElementRows` change what the toggles show and fire no action.
- **Selection is separate.** In a selectable `List`, a click on the Toggle changes the Toggle only: the row is not selected and the list's `actionID` does not fire. A click elsewhere in the row selects it and does not toggle. A selection resting on the toggled row stays on it.
- **Nested Toggles** (inside an `HStack` beside other views) behave the same.
- **Outside a template** nothing changes: a string `isOn` is invalid, `viewID` is the element's id, `viewPartID` is 0, and the state is the element's value.

For a checkbox column in a `Table`, see `Table` (`"viewType": "Toggle"`).

### Host differences

- **Styles.** `checkbox` is drawn on macOS, Web and Android; on iOS, iPadOS and visionOS it falls back to `switch`. `button` falls back to `switch` on Web and Android.
- **Web.** The toggled control keeps its place (the row is not rebuilt), so another view in the same row that shows the same column keeps its old text until the next rows change. Template containers on Web are `List`, `LazyVStack`, `LazyHStack`, `LazyVGrid` and `LazyHGrid`.
- **Web action context.** In a template the context is the plain Boolean, as on Apple and Android; outside a template the Web context stays `{ "isOn": Boolean }`.
