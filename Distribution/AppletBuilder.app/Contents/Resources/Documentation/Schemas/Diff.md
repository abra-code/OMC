# ActionUI.Diff

JSON schema and usage documentation for `Diff` (ActionUIDiff add-on).

```jsonc
// Add-ons/ActionUIDiff/Sources/ActionUIDiff/Diff.swift
// JSON specification for ActionUI.Diff:
 {
   "type": "Diff",
   "id": 1,                     // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "oldText": "func f() {}",           // Optional: Inline text for the OLD (left) side to compare
     "newText": "func f() { g() }",      // Optional: Inline text for the NEW (right) side to compare
     "oldFile": "~/before.swift",        // Optional: Absolute local path (tilde-expanded), read as UTF-8;
                                          //           used only when "oldText" is absent
     "newFile": "~/after.swift",         // Optional: Absolute local path (tilde-expanded), read as UTF-8;
                                          //           used only when "newText" is absent
     "contextLines": 3,                  // Optional: Int, default 3, >= 0; unchanged lines kept around each change
     "maxRenderedLines": 300             // Optional: Int, default 300, > 0; render cap before a truncation note
   }
 }
// An embedded unified line-diff viewer, implemented as an ActionUI add-on (registered via
// ActionUIDiff.register()). It renders the difference between two texts with the standalone DiffView
// component: hunks with old/new line-number gutters, +/- markers, tinted added/removed rows, "N
// unchanged lines" gaps where context collapsed, and honest degenerate cases (identical texts say "No
// changes"; oversized inputs fall back to a plain-text preview).
//
// DISPLAY-ONLY: the element has no observable value (valueType Void) - nothing to read back with
// getElementValue. What it shows lives entirely in its properties.
//
// All six properties are live: a setElementProperty after the element is displayed re-renders it. The
// wrapper is stateless - it builds the view from the current properties on every invocation, capturing
// nothing - so a host can drive the diff at runtime (e.g. inject oldFile / newFile paths resolved from
// a bundle) and the view updates.
//
// Per side, the text property WINS over the file property: if both "oldText" and "oldFile" are set the
// text is used and a warning is logged (same for the new side). A file path is tilde-expanded and read
// as UTF-8; a file that is missing, over 4 MB, or not valid UTF-8 renders an inline "Cannot read
// <path>" note instead of a misleading diff. A side with NEITHER text nor file is empty text - a
// legitimate new-file (all additions) or deleted-file (all removals) diff.
//
// Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity,
// cornerRadius, actionID, disabled, onAppearActionID, onDisappearActionID, etc.) are inherited from base View.
```
