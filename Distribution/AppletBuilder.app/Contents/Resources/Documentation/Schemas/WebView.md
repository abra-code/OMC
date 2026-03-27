# ActionUI.WebView

JSON schema and usage documentation for `WebView`.

```jsonc
// Sources/Views/WebView.swift
// JSON specification for ActionUI.WebView (iOS 26.0+ / macOS 26.0+ only):
 {
   "type": "WebView",
   "id": 1,              // Required: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "url": "https://www.swift.org",        // Optional: Initial URL to load; takes precedence over html
     "html": "<h1>Hello</h1>",             // Optional: Inline HTML to render (used when url is absent)
     "baseURL": "https://example.com",      // Optional: Base URL for resolving relative links in html content
     "customUserAgent": "MyApp/1.0",        // Optional: Overrides the default WebKit user agent string
     "backForwardNavigationGestures": true, // Optional: Bool, enable swipe back/forward gestures; default true
     "magnificationGestures": true,         // Optional: Bool, enable pinch-to-zoom; default true
     "linkPreviews": true,                  // Optional: Bool, enable long-press link previews; default true
     "limitsNavigationsToAppBoundDomains": false, // Optional: Bool; restrict navigation to app-bound domains; default false
     "upgradeKnownHostsToHTTPS": false,           // Optional: Bool; auto-upgrade known HTTP hosts to HTTPS; default false
     "userScripts": [   // Optional: JS injected on every page load via WKUserScript
       {
         "injectionTime": "documentStart", // Required: "documentStart" or "documentEnd"
         "source": "window.myFlag = true;", // One of source / filePath / resourceName is required:
         // "filePath": "/absolute/path/to/script.js",   absolute path to .js file on disk
         // "resourceName": "MyScript.js",               .js resource in the app's main bundle (.js extension optional)
         "forMainFrameOnly": false          // Optional Bool; false = inject into all frames; default false
       }
     ],
     "valueChangeActionID": "onURLChange",  // Optional: Fired when the page URL changes after navigation completes
     "navigationActionID": "onNavigation"   // Optional: Fired when isLoading changes (navigation started / finished)
   }
   // Note: Requires iOS 26.0+ / macOS 26.0+. On older OS versions a fallback Label is shown instead.
   // Note: userScripts are applied to WebPage.Configuration.userContentController at WebPage init time,
   //   so they persist across reloads but cannot be changed after the view is first rendered.
   //   Use "source" for inline JS, "filePath" for an absolute path to a .js file on disk, or
   //   "resourceName" to load a .js file from the app's main bundle (strip .js extension or include it).
   // Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity,
   // cornerRadius, actionID, disabled, onAppearActionID, onDisappearActionID, etc.) are inherited.
 }
// Observable state:
//   value (String)                      Current page URL (via getElementValue / setElementValue).
//                                       Write a URL string to navigate, or one of these commands:
//                                         "#goBack"    – navigate back  (no-op if canGoBack is false)
//                                         "#goForward" – navigate forward (no-op if canGoForward is false)
//                                         "#reload"    – reload the current page
//                                         "#stop"      – cancel an in-flight load
//   states["title"]            String?  Page <title> text; absent until first load completes.
//   states["isLoading"]        Bool     true while a navigation is in flight.
//   states["estimatedProgress"] Double  0.0–1.0 load progress.
//   states["canGoBack"]        Bool     Back list has entries.
//   states["canGoForward"]     Bool     Forward list has entries.
// All states accessible via getElementState / setElementState.
```
