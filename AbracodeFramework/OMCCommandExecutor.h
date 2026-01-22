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

+ (OSStatus)runCommand:(NSString *)inCommandNameOrId forCommandFile:(NSString *)inFileName withContext:(id)inContext useNavDialog:(BOOL)allowNavDialog delegate:(id)delegate;

@end
