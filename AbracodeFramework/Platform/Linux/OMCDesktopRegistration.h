//
//  OMCDesktopRegistration.h
//  Abracode
//
//  The Linux applet's first-launch check (design: Private/linux-applet-install-design.md, "Piece 3
//  plan"): whether this copy of the applet is on the desktop's app list, asked of its own install
//  script (Contents/Linux/install-applet.sh --status), and then:
//  - not on it: an alert offers to add it (the app list and the file managers' Services menu), with
//    Add, Not Now and Never (do not ask again);
//  - on it for a copy that is no longer there (the applet was moved): this copy is added without
//    asking;
//  - on it for this copy, for another copy that is there, or declined before: nothing.
//  The script does the work (--register, --decline). Nothing in a test launch, without the script,
//  or when the environment has COMMAND_ENGINE_NO_DESKTOP_PROMPT set (AppletBuilder's Run sets it for
//  the project it runs). Linux only; main thread only.
//

#pragma once

// Starts the check: returns at once; the script runs in the background and the alert, if any, comes
// once it answered. Called once the launch has finished.
void OMCOfferDesktopRegistration();
