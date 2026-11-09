//
//  OMCAppLifecycle.h
//  Abracode
//
//  What an applet does when the app launches, activates, deactivates and quits: portable C++ on
//  CF. The platform reports each event (on macOS, Platform/Apple/OMCAppLifecycleObserver.mm from
//  NSApplication's notifications); this runs the applet's lifecycle command for it (app.will.launch,
//  app.did.launch, app.did.activate, app.did.deactivate, app.will.terminate in Command.plist) and
//  the framework's own setup and teardown around it. Main thread.
//

#pragma once

enum class OMCAppLifecycleEvent
{
	WillLaunch,		// before the app handles any event: setup, then app.will.launch
	DidLaunch,		// app.did.launch
	DidActivate,	// app.did.activate
	DidDeactivate,	// app.did.deactivate
	WillTerminate	// app.will.terminate, then teardown
};

void OMCHandleAppLifecycleEvent(OMCAppLifecycleEvent inEvent) noexcept;
