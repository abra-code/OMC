/*
 *  DefaultExternBundle.h
 *  CommandDroplet
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

}; //extern "C"