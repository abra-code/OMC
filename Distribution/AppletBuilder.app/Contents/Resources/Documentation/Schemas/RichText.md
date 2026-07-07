# ActionUI.RichText

JSON schema and usage documentation for `RichText` (ActionUIRichText add-on).

```jsonc
// Add-ons/ActionUIRichText/Sources/RichText.swift
// JSON specification for ActionUI.RichText:
 {
   "type": "RichText",
   "id": 1,                  // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "markdown": "# Title\n\nA **bold** word, a `code` span, and a [link](https://example.com).",
                                             // Optional: Markdown source to render; seeds the element value.
                                             //           "" or nil renders an empty document.
     "baseFontSize": 15,                     // Optional: Number; base font point size. Omit for Dynamic Type body.
     "syntaxHighlighting": true              // Optional: Bool; color fenced code blocks by language. Default from
                                             //           the RichText theme.
   }
 }
// A rich-text DISPLAY element backed by the RichText package, implemented as an ActionUI add-on
// (registered via ActionUIRichText.register()):
//   macOS / iOS / visionOS - RichText.RichText (a SwiftUI View; RichText's platforms).
// A whole Markdown document (headings, code blocks, quotes, lists, GFM tables, inline styling, links) is
// laid out into ONE native text view, so the entire document is selectable and copyable as a single unit
// (copy is table-aware: RTF / HTML / Markdown).
//
// Observable state (via getElementValue / setElementValue):
//   value (String)   Current Markdown source. Write new Markdown to re-render; "" or nil renders empty.
//
// Note: baseline View properties (padding, hidden, background, frame, opacity, cornerRadius, actionID,
// onAppearActionID, onDisappearActionID, etc.) are inherited from base View. The document is read-only but
// selectable, self-sizes to its content for the proposed width, and handles its own links (http/https/mailto/tel).
```
