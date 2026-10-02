//
//  OMCCommandExecutor.h
//  Abracode
//
//  Created by Tomasz Kukielka on 4/6/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface OMCCommandExecutor : NSObject

/// inFileName param may be:
/// - a name of the command plist file to find in app host bundle (main bundle)
/// - an absolute path to command plist
/// - an absolute path to .omc bundle, with contains command description in Bundle.omc/Contents/Resources/Command.plist
 
/// The delegate parameter in runCommand:... can conform to OMCObserverDelegate
/// If it does, runCommand will:
/// 1. Create an OMCObserverRef via OMCCreateObserver
/// 2. Call [delegate setObserver:] to pass ownership of the OMCObserverRef to the delegate
/// 3. Add the observer to the executor
/// 4. The delegate will receive callbacks via receiveObserverMessage:forTaskId:withData:

/// When param useNavDialog = TRUE, missing file context is obtained from nav dialog
/// otherwise when the file context is missing the command is not executed
/// if USE_NAV_DIALOG_FOR_MISSING_FILE_CONTEXT is false, the command always executes and no nav dialog is shown

+ (OSStatus)runCommand:(NSString *)inCommandNameOrId forCommandFile:(NSString *)inFileName withContext:(id)inContext useNavDialog:(BOOL)allowNavDialog allowKeyWindowSubcommand:(BOOL)allowKeyWindowSubcommand delegate:(id)delegate;

/// Runs the command a URL sent to the applet asks for. A URL is untrusted input: any web page,
/// document or other application can send one, so this is the only entry point that applies
/// the URL rules, and URL handling must go through it rather than through runCommand:...
///
/// <scheme>://exe?commandID=<id>[&text=<text>][&file=<absolute path>]...
///   Runs command <id> only if it sets URL_INVOCABLE to true in the command description.
///   Application lifecycle commands (app.will.terminate, ...) and dialog event handlers
///   (INIT_SUBCOMMAND_ID, END_OK_SUBCOMMAND_ID, ...) are refused whatever the key says.
///   "text" becomes the text context, "file" (repeatable) the file context; files win over text.
///   Each "file" must be an absolute path of an existing item, or the whole URL is refused.
/// any other URL
///   Runs the command with id omc.app.handle-url, if the applet has one, with the whole URL
///   as text context. That command needs no key: receiving URLs is all it is for.
///
/// The URL is exported to the command chain as OMC_TRIGGER_URL, absent for every other run.
/// A refused URL runs nothing, logs one line saying why and returns errAEEventNotPermitted.

+ (OSStatus)runCommandForURL:(NSString *)inURLString forCommandFile:(NSString *)inFileName delegate:(id)delegate;

@end
