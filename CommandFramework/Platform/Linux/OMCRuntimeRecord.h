//
//  OMCRuntimeRecord.h
//  Command
//
//  Which Swift runtime line this applet uses, written down for command-engine-cleanup (design:
//  Private/linux-applet-install-design.md, "Decisions, 2026-11-16", item 7). The command-engine
//  package makes /var/lib/command-engine/applets/ writable by everyone (sticky, like /tmp); at each
//  launch the applet adds the line "<runtime line><TAB><bundle path>" to <uid>.list there, once.
//  The runtime line is the folder the Swift runtime was actually loaded from
//  (/usr/lib/command-engine/swift-6.4/libswiftCore.so gives swift-6.4); a development build that
//  runs on the toolchain's own runtime records nothing, nor does a machine without the folder (no
//  command-engine package). Every launch, not only a registered one: an applet whose user declined the
//  desktop entry still needs its runtime. Nothing in a test launch. Linux only.
//

#pragma once

// Adds this launch's record when it is not there yet; failures are logged, never shown
void OMCRecordRuntimeUse();
