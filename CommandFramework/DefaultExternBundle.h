/*
 *  DefaultExternBundle.h
 *  OMCApplet
 *
 *  Created by Tomasz Kukielka on 9/8/06.
 *  Copyright 2006 Abracode. All rights reserved.
 *
 */
#include <CoreFoundation/CoreFoundation.h>

extern "C"
{
CFURLRef CreateDefaultExternBundleURL(CFArrayRef inCommandName);
CFStringRef CreateDefaultExternBundleString(CFArrayRef inCommandName);
CFBundleRef CreateDefaultExternBundleRef(CFArrayRef inCommandName);

// The bundle at inBundleURL, made absolute first; NULL when there is none
CFBundleRef CreateBundleFromURL(CFURLRef inBundleURL);

// Whether commands running in inMainBundle's process may take their scripts, windows and strings
// from the implicit ~/Library/Application Support/OnMyCommand/<NAME>.omc bundle: only when the main
// bundle has no command file of its own (the contextual menu host), never in an applet
bool OMCHostUsesDefaultExternBundles(CFBundleRef inMainBundle);

}; //extern "C"