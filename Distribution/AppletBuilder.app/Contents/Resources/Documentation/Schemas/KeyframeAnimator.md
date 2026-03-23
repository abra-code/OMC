# ActionUI.KeyframeAnimator

JSON schema and usage documentation for `KeyframeAnimator`.

```jsonc
// Sources/Views/KeyframeAnimator.swift
// JSON specification for ActionUI.KeyframeAnimator:
 {
   "type": "KeyframeAnimator",
   "id": 1,
   "content": {          // Required: Single child view. Note: Declared as a top-level key in JSON but stored in subviews["content"] by ActionUIElement.init(from:).
     "type": "Text", "properties": { "text": "Animating" }
   },
   "properties": {
     "initialValue": { "opacity": 0.0, "scale": 1.0, "rotation": 0.0 },
     "trigger": "onAppear", // "onAppear", "onTap", "onTimer", "onStateChange"
     "timerInterval": 2.0, // Optional, for onTimer
     "stateKey": "counter", // Optional, for onStateChange
     "repeat": { "count": 3, "autoreverses": true }, // Optional
     "delay": 1.0, // Optional
     "keyframes": {
       "0%": { "type": "linear", "value": { "opacity": 0.0, "scale": 0.5 }, "duration": 0.8 },
       "50%": { "type": "spring", "value": { "opacity": 1.0, "scale": 1.5 }, "duration": 0.5, "response": 0.4, "dampingRatio": 0.6 },
       "100%": { "type": "cubic", "value": { "opacity": 0.5, "scale": 1.0 }, "duration": 0.6, "startVelocity": 0.2, "endVelocity": 0.4 },
       "25%": { "type": "spring", "value": { "opacity": 0.5 }, "duration": 0.4, "response": 0.5, "dampingRatio": 1.0 }
     }
   }
 }
// Observable state:
//   states["currentRepeatCount"] Int   Number of completed animation cycles since the view appeared.
//                                      Written by the view after each cycle; treat as read-only from the
//                                      host app (via getElementState).
//   states[stateKey]             Int   When trigger is "onStateChange", increment this Int (named by the
//                                      "stateKey" property, defaults to "counter") to fire the next
//                                      animation cycle (via setElementState).
```
