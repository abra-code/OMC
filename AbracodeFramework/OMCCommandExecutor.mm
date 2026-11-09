//
//  OMCCommandExecutor.m
//  Abracode
//
//  Created by Tomasz Kukielka on 4/6/08.
//  Copyright 2008 Abracode. All rights reserved.
//
//  The Objective-C entry for running commands (menus, the droplet, lifetime events, services).
//  The rules live in the portable OMCCommandRunner; this class adds what only macOS has: the key
//  window's controller, Open Recent, the delegate as an observer, and NSURLComponents for URLs.
//

#import "OMCCommandExecutor.h"
#import "OMCWindowController.h"
#include "OMCActionUIWindow.h"
#include "OMC.h"
#include "OMCCommandRunner.h"
#include "OMCURLParse.h"
#include "OMCTestHost.h"
#import "OMCObserverDelegate.h"

void OMCDelegateObserverCallback(OmcObserverMessage inMessage, CFIndex inTaskID, CFTypeRef inResult, void *userData)
{
    if (userData == NULL)
    {
        return;
    }

    id __weak objcObject = (__bridge id)userData;
    if ([objcObject conformsToProtocol:@protocol(OMCObserverDelegate)])
    {
        id<OMCObserverDelegate> __strong observerDelegate = (id<OMCObserverDelegate>)objcObject;
        [observerDelegate receiveObserverMessage:inMessage forTaskId:inTaskID withData:inResult];
    }
}

// What a run needs from macOS. Lives on the stack for the length of one call.
struct OMCExecutorHookContext
{
    __unsafe_unretained id delegate;
};

static bool DispatchToKeyWindow(void *inHookContext, CFStringRef inCommandNameOrId, CFTypeRef inContext)
{
    (void)inHookContext;
    // An ActionUI command window, else a nib dialog
    if(std::shared_ptr<OMCActionUIWindow> keyWindow = OMCActionUIWindow::FindKeyWindow())
    {
        keyWindow->DispatchCommand(inCommandNameOrId, inContext);
        return true;
    }
    OMCWindowController *keyWindowController = [OMCWindowController findControllerForKeyWindow];
    if (keyWindowController == nil)
        return false;
    [keyWindowController dispatchCommand:(__bridge NSString *)inCommandNameOrId withContext:inContext];
    return true;
}

void OMCNoteRecentDocumentURL(NSURL *inURL)
{
    if(inURL == nil)
        return;
    // A test launch works on the test's own files, deleted when it ends. The recent documents
    // are kept per user, not under the test's private HOME, so recording them would fill the
    // user's real Open Recent menu and Recent Items and push the user's own entries out, and
    // then leave entries for files that no longer exist.
    if(OMCTestHostIsActive())
    {
        OMCTestHostNoteSkippedRecentDocument();
        return;
    }
    [NSDocumentController.sharedDocumentController noteNewRecentDocumentURL:inURL];
}

static void NoteRecentFiles(void *inHookContext, CFArrayRef inFileURLs)
{
    (void)inHookContext;
    NSArray<NSURL*> *__weak absoluteURLArray = (__bridge NSArray<NSURL*> *)inFileURLs;
    for (NSURL *oneFileURL in absoluteURLArray)
    {
        OMCNoteRecentDocumentURL(oneFileURL);
    }
}

static OMCObserverRef CreateDelegateObserver(void *inHookContext)
{
    OMCExecutorHookContext *hookContext = (OMCExecutorHookContext *)inHookContext;
    id delegate = hookContext->delegate;
    if ((delegate == nil) || ![delegate conformsToProtocol:@protocol(OMCObserverDelegate)])
        return NULL;

    id<OMCObserverDelegate> observerDelegate = (id<OMCObserverDelegate>)delegate;
    // Create observer with the delegate as userData (stored weakly there)
    OMCObserverRef observer = OMCCreateObserver(kOmcObserverAllMessages,
                                                 OMCDelegateObserverCallback,
                                                 (__bridge void *)observerDelegate);
    if (observer != NULL)
        [observerDelegate setObserver:observer]; // Delegate takes the ownership of the observer and retains it
    return observer; // the runner adds it to the run and releases this reference
}

static OMCRunHooks MakeHooks(OMCExecutorHookContext *inHookContext)
{
    OMCRunHooks hooks;
    hooks.dispatchToKeyWindow = DispatchToKeyWindow;
    hooks.noteRecentFiles = NoteRecentFiles;
    hooks.createObserver = CreateDelegateObserver;
    hooks.context = inHookContext;
    return hooks;
}

@implementation OMCCommandExecutor

//when useNavDialog = TRUE, missing file context is obtained from nav dialog
//otherwise when the file context is missing the command is not executed
//if USE_NAV_DIALOG_FOR_MISSING_FILE_CONTEXT is false, the command always executes and no nav dialog is shown
+ (OSStatus)runCommand:(NSString *)inCommandNameOrId forCommandFile:(NSString *)inFileName withContext:(id)inContext useNavDialog:(BOOL)clientAllowsNavDialog allowKeyWindowSubcommand:(BOOL)allowKeyWindowSubcommand delegate:(id)delegate
{
    OMCExecutorHookContext hookContext = { delegate };
    OMCRunHooks hooks = MakeHooks(&hookContext);
    return OMCRunCommandFromFile((__bridge CFStringRef)inCommandNameOrId, (__bridge CFStringRef)inFileName, (__bridge CFTypeRef)inContext,
                                 clientAllowsNavDialog, allowKeyWindowSubcommand, NULL, false, &hooks);
}

+ (OSStatus)runCommandForURL:(NSString *)inURLString forCommandFile:(NSString *)inFileName delegate:(id)delegate
{
    OMCExecutorHookContext hookContext = { delegate };
    OMCRunHooks hooks = MakeHooks(&hookContext);

    // The URL is parsed by OMCParseURL, which keeps NSURLComponents' rules (OMCURLParse.h); the
    // decisions about what the URL may run are OMCRunCommandForURL's
    CFObj<CFStringRef> host;
    CFObj<CFArrayRef> queryItems;
    bool isValidURL = ([inURLString length] > 0) && OMCParseURL((__bridge CFStringRef)inURLString, host, queryItems);
    return OMCRunCommandForURL((__bridge CFStringRef)inURLString, isValidURL, host, queryItems, (__bridge CFStringRef)inFileName, &hooks);
}

@end
