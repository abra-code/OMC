# ActionUI.PhaseAnimator

JSON schema and usage documentation for `PhaseAnimator`.

```jsonc
// Sources/Views/PhaseAnimator.swift
// JSON specification for ActionUI.PhaseAnimator:
 {
   "type": "PhaseAnimator",
   "id": 1,
   "content": {          // Required: Single child view. Note: Declared as a top-level key in JSON but stored in subviews["content"] by ActionUIElement.init(from:).
     "type": "Text", "properties": { "text": "Animating" }
   },
   "properties": {
     "values": [0.0, 1.0, 2.0],
     "trigger": "onAppear", // "onAppear", "onTap", "onTimer", "onStateChange"
     "timerInterval": 2.0, // Optional, for onTimer
     "stateKey": "counter", // Optional, for onStateChange
     "animation": {
       "type": "spring", // linear, easeIn, easeOut, easeInOut, spring, interactiveSpring, smooth, bouncy, timingCurve
       "duration": 0.5, // For linear, easeIn, easeOut, easeInOut, smooth, bouncy, timingCurve
       "response": 0.5, // For spring, interactiveSpring
       "dampingFraction": 0.7, // Optional for spring, interactiveSpring
       "blendDuration": 0.0, // Optional for spring, interactiveSpring
       "extraBounce": 0.1, // Optional for smooth, bouncy
       "controlPoints": [0.2, 0.8, 0.4, 1.0] // For timingCurve (c0x, c0y, c1x, c1y)
     }
   }
 }
// Observable state:
//   states[stateKey] Int   When trigger is "onStateChange", increment this Int (named by the
//                          "stateKey" property, defaults to "counter") to fire the next animation
//                          cycle (via getElementState / setElementState).
```
