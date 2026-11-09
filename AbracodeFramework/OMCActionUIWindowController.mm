//
//  OMCActionUIWindowController.mm
//  Abracode
//
//  Created by Tomasz Kukielka on 2/17/26.
//  Copyright 2026 Abracode. All rights reserved.
//

#import "OMCActionUIWindowController.h"
#import "OMCCommandExecutor.h"
#include "OMCControlAccessorBridge.h"
#import "OMCActionUIDialog.h"
#import "OMCControlAccessor.h"
#include "OnMyCommand.h"
#include "CommandRuntimeData.h"
#include "ACFDict.h"
#include "OMCStrings.h"
#include "OMCActionUIModelLifetime.h"
#include "OMCWindowHost.h"
#include "OMCActionUIDocumentLookup.h"
#include "OMCActionUIControls.h"
#include <memory>

// enable only in OMC version 5.0 or later
#if CURRENT_OMC_VERSION >= 50000
@import ActionUIObjCAdapter;

#import "OMCActionUIRemoteHost.h"

/// Converts the opaque ActionUI action-callback context to a string suitable for env-var export.
/// NSDictionary/NSArray to compact JSON
/// NSNumber to numeric string
/// NSString: as-is.
static NSString *SerializeActionContext(id context)
{
    if (context == nil)
        return nil;
    if ([context isKindOfClass:[NSString class]])
        return (NSString *)context;
    if ([context isKindOfClass:[NSNumber class]])
        return [(NSNumber *)context stringValue];
    if ([context isKindOfClass:[NSDictionary class]] || [context isKindOfClass:[NSArray class]]) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:context options:0 error:nil];
        if (data != nil)
            return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return [context description];
}

@implementation OMCActionUIWindowController
{
    // The window, made by the window host (Platform/OMCWindowHost.h); nullptr when the command names
    // no document or it cannot be loaded. The host's delegate gets the window's close and key
    // notifications and passes them to this controller.
    std::unique_ptr<OMCHostedWindow> mHostedWindow;
}

// Command.plist SCHEMA SOURCE OF TRUTH — ACTIONUI_WINDOW (JSON_NAME, WINDOW_TYPE enum
// [floating/global_floating], INIT_SUBCOMMAND_ID, END_OK_SUBCOMMAND_ID,
// END_CANCEL_SUBCOMMAND_ID, WINDOW_DID_ACTIVATE_SUBCOMMAND_ID,
// WINDOW_DID_DEACTIVATE_SUBCOMMAND_ID). JSON_NAME resolves to a .json anywhere under
// Resources (root / localized .lproj); the subcommand-ID keys reference COMMAND_IDs.
// Adding/removing/renaming/deprecating/retyping any key (or enum value) here REQUIRES updating
// the matching verifier schema and rebuilding the skill, else the Command.plist verifier drifts:
//   verifier schema: Distribution/AppletBuilder.app/Contents/Library/command_verifier/schemas/ACTIONUI_WINDOW.json
//   rebuild skill:   python3 Skill/build_skill.py
- (id)initWithOmc:(OnMyCommand *)inOmc commandRuntimeData:(CommandRuntimeData *)inCommandRuntimeData
{
   self = [super initWithOmc:inOmc commandRuntimeData:inCommandRuntimeData];
	if(self == nil)
		return nil;

    mOMCDialogProxy.Adopt( new OMCActionUIDialog() );
    mOMCDialogProxy->SetControlAccessor(OMCMakeControlAccessorBridge(self));
    self->mCommandRuntimeData->SetAssociatedDialogUUID(mOMCDialogProxy->GetDialogUUID());

    // The window now has a UUID, which is the only thing a remote client needs to address it, so
    // this is the earliest point at which serving is meaningful - and it is before the init
    // subcommand runs, so that subcommand's own handler can already reach back in. Idempotent:
    // every later window finds the server already up.
    OMCEnsureActionUIRemoteBridgeStarted();

	CommandDescription &currCommand = self->mPlugin->GetCurrentCommand();

	ACFDict params( currCommand.actionUIWindow );
    CFObj<CFStringRef> jsonName;
	params.CopyValue( CFSTR("JSON_NAME"), jsonName );

	if(jsonName == nullptr)
		return self;//no json name, no dialog
    
    NSString *__strong dialogJsonName = (NSString *)CFBridgingRelease(jsonName.Detach());

    CFObj<CFStringRef> initSubcommandID;
	params.CopyValue( CFSTR("INIT_SUBCOMMAND_ID"), initSubcommandID );
    self.dialogInitSubcommandID = (NSString *)CFBridgingRelease(initSubcommandID.Detach());
    
    CFObj<CFStringRef> endOKSubcommandID;
	params.CopyValue( CFSTR("END_OK_SUBCOMMAND_ID"), endOKSubcommandID );
    self.endOKSubcommandID = (NSString *)CFBridgingRelease(endOKSubcommandID.Detach());

    CFObj<CFStringRef> endCancelSubcommandID;
	params.CopyValue( CFSTR("END_CANCEL_SUBCOMMAND_ID"), endCancelSubcommandID );
    self.endCancelSubcommandID = (NSString *)CFBridgingRelease(endCancelSubcommandID.Detach());

    CFObj<CFStringRef> windowDidActivateID;
	params.CopyValue( CFSTR("WINDOW_DID_ACTIVATE_SUBCOMMAND_ID"), windowDidActivateID );
    self.windowDidActivateSubcommandID = (NSString *)CFBridgingRelease(windowDidActivateID.Detach());

    CFObj<CFStringRef> windowDidDeactivateID;
	params.CopyValue( CFSTR("WINDOW_DID_DEACTIVATE_SUBCOMMAND_ID"), windowDidDeactivateID );
    self.windowDidDeactivateSubcommandID = (NSString *)CFBridgingRelease(windowDidDeactivateID.Detach());

	Boolean isBlocking = true;//default is modal
	params.GetValue( CFSTR("IS_BLOCKING"), isBlocking );
	mIsModal = isBlocking;

    CFObj<CFStringRef> windowTitle;
    params.CopyValue( CFSTR("WINDOW_TITLE"), windowTitle );

    CFStringRef windowType = nullptr;
    params.GetValue( CFSTR("WINDOW_TYPE"), windowType );

	//now we need to find out where our json is
	NSURL *jsonURL = [self resolveJSONURL:dialogJsonName];

#if DEBUG
	NSLog(@"[OMCActionUIWindowController initWithOmc], jsonURL=%@", jsonURL);
#endif

    if(jsonURL == nil)
    {
        NSLog(@"Cannot find ActionUI JSON file: %@", dialogJsonName);
        return self;
    }

    // The window host makes the window: the content spans the titlebar (required for a SwiftUI
    // NavigationSplitView root, see OMCWindowHost.mm), the size limits come from the document, a
    // document of fixed size makes a window the user cannot resize, and the frame saved under
    // "OMC.<JSON_NAME>" comes back, else the window opens at its fitting size, centered.
    NSString *autosaveName = [NSString stringWithFormat:@"OMC.%@", dialogJsonName];
    OMCHostedWindowSpec spec;
    spec.documentURL = (__bridge CFURLRef)jsonURL;
    spec.windowUUID = mOMCDialogProxy->GetDialogUUID();
    spec.frameAutosaveName = (__bridge CFStringRef)autosaveName;
    spec.placement = OMCHostedWindowPlacement::restoredElseCentered;
    spec.contentSpansTitlebar = true;
    spec.sizeLimitsFromDocument = true;
    // The window's model outlives the window until the last command started for it has ended
    // (OMCActionUIModelLifetime.h, see dealloc)
    spec.removesModelWhenDestroyed = false;
    // A regular non-blocking window gets the minimize button, and with it a working Window >
    // Minimize (Cmd-M): NSWindow disables performMiniaturize: for a window without this bit.
    // A blocking dialog runs in a modal session, and minimizing it would leave the app stuck
    // behind an invisible modal window. Floating panels follow the system convention for panels,
    // which do not minimize (the host gives no panel the button).
    spec.miniaturizable = !mIsModal;
    if(windowType != nullptr)
    {
        if( kCFCompareEqualTo == ::CFStringCompare( windowType, CFSTR("floating"), 0 ) )
            spec.level = OMCHostedWindowLevel::floating;
        else if( kCFCompareEqualTo == ::CFStringCompare( windowType, CFSTR("global_floating"), 0 ) )
            spec.level = OMCHostedWindowLevel::utility;
        // "regular" is the default, no changes needed
    }

    // Every close of the window, the user's or this controller's (-[NSWindow close]), reaches
    // windowWillClose:, which runs the end subcommand. The host holds these callbacks and this
    // controller holds the host, so they capture the controller weakly.
    __weak OMCActionUIWindowController *weakSelf = self;
    mHostedWindow = OMCCreateHostedWindow(spec, [weakSelf]() {
        OMCActionUIWindowController *strongSelf = weakSelf;
        [strongSelf windowWillClose:[NSNotification notificationWithName:NSWindowWillCloseNotification object:strongSelf.window]];
    });
    if(mHostedWindow == nullptr)
    {
        NSLog(@"Unable to create a view from ActionUI JSON file: %@", dialogJsonName);
        return self;
    }
    mHostedWindow->SetKeyChangeCallbacks(
        [weakSelf]() {
            OMCActionUIWindowController *strongSelf = weakSelf;
            [strongSelf windowDidBecomeKey:[NSNotification notificationWithName:NSWindowDidBecomeKeyNotification object:strongSelf.window]];
        },
        [weakSelf]() {
            OMCActionUIWindowController *strongSelf = weakSelf;
            [strongSelf windowDidResignKey:[NSNotification notificationWithName:NSWindowDidResignKeyNotification object:strongSelf.window]];
        });

    self.window = (__bridge NSWindow *)mHostedWindow->GetNativeWindow();

    // Set window title: WINDOW_TITLE param > associated file > dynamic command name
    if(windowTitle != nullptr)
    {
        mHostedWindow->SetTitle(windowTitle);
    }
    else
    {
        OneObjProperties *associatedObj = mCommandRuntimeData->GetAssociatedObject();
        if(associatedObj != nullptr)
        {
            CFURLRef fileURL = associatedObj->url.Get();
            if(fileURL != NULL)
            {
                mHostedWindow->SetRepresentedFile(fileURL);
                OMCNoteRecentDocumentURL((__bridge NSURL *)fileURL);
            }
        }
        else
        {
            CFBundleRef localizationBundle = NULL;
            if(currCommand.localizationTableName != NULL)//client wants to be localized
            {
                localizationBundle = self->mPlugin->GetCurrentCommandExternBundle();
                if(localizationBundle == NULL)
                    localizationBundle = CFBundleGetMainBundle();
            }

            CFObj<CFStringRef> dynamicCommandName( self->mPlugin->CreateDynamicCommandName(currCommand,
                                                                                      *mCommandRuntimeData,
                                                                                      currCommand.localizationTableName,
                                                                                      localizationBundle) );
            mHostedWindow->SetTitle(dynamicCommandName);
        }
    }

    // Global default handler — routes by windowUUID to the right controller instance.
    // Set once for all windows since it finds the controller by UUID anyway.
    static dispatch_once_t actionHandlerOnceToken;
    dispatch_once(&actionHandlerOnceToken, ^{
        [ActionUIObjC setDefaultActionHandler:^(NSString *actionID, NSString *targetWindowUUID, NSInteger viewID, NSInteger viewPartID, id context) {
            OMCWindowController *controller = [OMCWindowController findControllerByUUID:targetWindowUUID];
            if (controller != nil)
            {
                // Carry ActionUI's control-trigger context into the subcommand via CommandRuntimeData.
                // The OMC command context (files/text) is unaffected — inContext stays nil.
                NSString *contextString = SerializeActionContext(context);
                [controller setControlContextViewID:viewID viewPartID:viewPartID contextString:contextString];
                [controller dispatchCommand:actionID withContext:nil];
                [controller clearControlContext];
            }
            else
            {
                NSLog(@"Window not found for provided UUID: %@ when handling actionID: %@ from viewID: %ld", targetWindowUUID, actionID, static_cast<long>(viewID));
            }
        }];
    });

    return self;
}

#pragma mark - Window geometry, through the window host

/// omc_dialog_control's "omc_window omc_resize W H" names the layout area, as it always has; the
/// content view also spans the titlebar, which the host adds.
- (void)setWindowContentSize:(NSSize)inContentSize
{
    if(mHostedWindow != nullptr)
        mHostedWindow->SetLayoutSize(inContentSize.width, inContentSize.height);
}

/// omc_dialog_control's "omc_window omc_move X Y": the top-left corner, from the top-left corner of
/// the main screen's visible area
- (void)setWindowTopLeftPosition:(NSPoint)absolutePosition
{
    if(mHostedWindow != nullptr)
        mHostedWindow->SetTopLeftPosition(absolutePosition.x, absolutePosition.y);
}

#pragma mark -

- (void)dealloc
{
    OMCActionUIDialog *actionUIDialog = (OMCActionUIDialog *)mOMCDialogProxy.Get();
    if(actionUIDialog != nullptr)
        actionUIDialog->SetControlAccessor(nullptr);

    // The host closes the window if it is still open and takes the hosting view out of it. Not
    // here: this controller usually goes at the end of its windowWillClose:, which may run inside
    // the window's own button action (an OK or Cancel button), with the window still posting its
    // will-close notification. On the main queue the hosting view stays in the window until that
    // has finished, as the output window does (OutputWindowHandler.cp); main thread only, too.
    if(mHostedWindow != nullptr)
    {
        OMCHostedWindow *hostedWindow = mHostedWindow.release();
        dispatch_async(dispatch_get_main_queue(), ^{ delete hostedWindow; });
    }

    // The window's ActionUI model (its description, values and states) outlives this controller
    // until the last command started for the window has ended: the end command, which starts as
    // the window closes, may read the closed window through the ActionUI remote bridge
    // (OMCActionUIModelLifetime.h). Without the removal every window the applet ever showed would
    // stay in ActionUI (and in actionui.listWindows) for the life of the process. The hosting view
    // may outlive the model (the window's content view holds it until the window goes), which is
    // harmless: an ActionUI view without a model draws a placeholder. Main thread only, like
    // ActionUI's model; a dealloc elsewhere hands it to the main queue.
    NSString *windowUUID = nil;
    if(mOMCDialogProxy.Get() != nullptr)
        windowUUID = [(__bridge NSString *)mOMCDialogProxy->GetDialogUUID() copy];
    if(windowUUID != nil)
    {
        if([NSThread isMainThread])
            OMCActionUIModelWindowClosed((__bridge CFStringRef)windowUUID);
        else
            dispatch_async(dispatch_get_main_queue(), ^{ OMCActionUIModelWindowClosed((__bridge CFStringRef)windowUUID); });
    }
}

#pragma mark - OMCControlAccessor protocol

// The control operations are portable C++ over ActionUI's C interface (OMCActionUIControls.h)

- (void)setControlStringValue:(NSString *)inValue forControlID:(NSString *)inControlID contentType:(NSString *)contentType
{
    OMCActionUISetControlValue(mOMCDialogProxy->GetDialogUUID(), (__bridge CFStringRef)inControlID,
                               (__bridge CFStringRef)inValue, (__bridge CFStringRef)contentType);
}

- (void)setControlEnabled:(BOOL)enabled forControlID:(NSString *)inControlID
{
    OMCActionUISetControlEnabled(mOMCDialogProxy->GetDialogUUID(), (__bridge CFStringRef)inControlID, enabled);
}

- (void)setControlVisible:(BOOL)visible forControlID:(NSString *)inControlID
{
    OMCActionUISetControlVisible(mOMCDialogProxy->GetDialogUUID(), (__bridge CFStringRef)inControlID, visible);
}

- (void)setPropertyKey:(NSString *)propertyKey jsonValue:(NSString *)jsonValue forControlID:(NSString *)inControlID
{
    OMCActionUISetControlProperty(mOMCDialogProxy->GetDialogUUID(), (__bridge CFStringRef)inControlID,
                                  (__bridge CFStringRef)propertyKey, (__bridge CFStringRef)jsonValue);
}

- (void)setStateKey:(NSString *)stateKey stringOrJsonValue:(NSString *)value forControlID:(NSString *)inControlID
{
    OMCActionUISetControlState(mOMCDialogProxy->GetDialogUUID(), (__bridge CFStringRef)inControlID,
                               (__bridge CFStringRef)stateKey, (__bridge CFStringRef)value);
}

#pragma mark - List controls

- (void)removeAllListItemsForControlID:(NSString *)inControlID
{
    OMCActionUIClearControlRows(mOMCDialogProxy->GetDialogUUID(), (__bridge CFStringRef)inControlID);
}

- (void)setListItems:(CFArrayRef)items forControlID:(NSString *)inControlID
{
    OMCActionUISetControlListItems(mOMCDialogProxy->GetDialogUUID(), (__bridge CFStringRef)inControlID, items);
}

- (void)appendListItems:(CFArrayRef)items forControlID:(NSString *)inControlID
{
    OMCActionUIAppendControlListItems(mOMCDialogProxy->GetDialogUUID(), (__bridge CFStringRef)inControlID, items);
}

#pragma mark - Control layout and focus (not applicable to declarative SwiftUI layout)

- (void)selectControlWithID:(NSString *)inControlID
{
    NSLog(@"[OMCActionUIWindowController] selectControlWithID: %@ — not yet implemented (requires @FocusState wiring)", inControlID);
}

- (void)setCommandID:(NSString *)commandID forControlID:(NSString *)inControlID
{
    NSLog(@"[OMCActionUIWindowController] setCommandID:%@ forControlID: %@ — not supported (ActionUI actions are declared in JSON at load time)", commandID, inControlID);
}

- (void)moveControlWithID:(NSString *)inControlID toPosition:(NSPoint)position
{
    NSLog(@"[OMCActionUIWindowController] moveControlWithID: %@ — not supported (SwiftUI uses declarative layout)", inControlID);
}

- (void)resizeControlWithID:(NSString *)inControlID toSize:(NSSize)size
{
    NSLog(@"[OMCActionUIWindowController] resizeControlWithID: %@ — not supported (SwiftUI uses declarative layout)", inControlID);
}

- (void)scrollControlWithID:(NSString *)inControlID toPosition:(NSPoint)position
{
    NSLog(@"[OMCActionUIWindowController] scrollControlWithID: %@ — not yet implemented", inControlID);
}

- (void)invokeMessagesForControlID:(NSString *)inControlID messages:(CFArrayRef)messages
{
    NSLog(@"[OMCActionUIWindowController] invokeMessagesForControlID: %@ — not supported (ActionUI views do not expose an ObjC message dispatch interface)", inControlID);
}

- (void)allControlValues:(NSMutableDictionary *)ioControlValues andProperties:(NSMutableDictionary *)ioCustomProperties withIterator:(SelectionIterator *)inSelIterator
{
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if(windowUUID == nil)
        return;

    NSDictionary *elementInfo = [ActionUIObjC getElementInfoWithWindowUUID:windowUUID];
    if(elementInfo == nil || elementInfo.count == 0)
        return;

    for(NSNumber *viewIDNumber in elementInfo)
    {
        NSInteger viewID = [viewIDNumber integerValue];
        NSString *controlID = [viewIDNumber stringValue];

        NSInteger columnCount = [ActionUIObjC getElementColumnCountWithWindowUUID:windowUUID viewID:viewID];
        if(columnCount > 0)
        {
            // Table: store key "0" (tab-joined selected row) plus one key per column (1..columnCount).
            // Column keys are always stored so OMC_ACTIONUI_TABLE_N_COLUMN_M_VALUE is exported
            // even when no row is selected (in which case values are empty strings).
            NSMutableDictionary *partsDict = [NSMutableDictionary dictionaryWithCapacity:columnCount + 1];
            partsDict[@"0"] = [ActionUIObjC getElementValueAsStringWithWindowUUID:windowUUID viewID:viewID viewPartID:0 contentType:nil] ?: @"";
            for(NSInteger colIdx = 1; colIdx <= columnCount; colIdx++)
            {
                NSString *colKey = [NSString stringWithFormat:@"%ld", (long)colIdx];
                partsDict[colKey] = [ActionUIObjC getElementValueAsStringWithWindowUUID:windowUUID viewID:viewID viewPartID:colIdx contentType:nil] ?: @"";
            }
            ioControlValues[controlID] = partsDict;
        }
        else
        {
            // Non-table: single value under key "0"
            NSString *value = [ActionUIObjC getElementValueAsStringWithWindowUUID:windowUUID viewID:viewID viewPartID:0 contentType:nil];
            if(value != nil)
            {
                ioControlValues[controlID] = [NSMutableDictionary dictionaryWithObject:value forKey:@"0"];
            }
        }
    }
}

- (id)controlValueForID:(NSString *)inControlID forPart:(NSString *)inControlPart withIterator:(SelectionIterator *)inSelIterator outProperties:(CFDictionaryRef *)outCustomProperties
{
    if(outCustomProperties != NULL)
        *outCustomProperties = NULL;

    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if(windowUUID == nil)
        return nil;

    NSInteger viewID = [inControlID integerValue];
    NSInteger viewPartID = (inControlPart != nil) ? [inControlPart integerValue] : 0;

    NSString *value = [ActionUIObjC getElementValueAsStringWithWindowUUID:windowUUID viewID:viewID viewPartID:viewPartID contentType:nil];
    return value;
}

#pragma mark - Table setters

- (void)emptyTableForControlID:(NSString *)inControlID
{
    OMCActionUIClearControlRows(mOMCDialogProxy->GetDialogUUID(), (__bridge CFStringRef)inControlID);
}

- (void)removeTableRowsForControlID:(NSString *)inControlID
{
    // Same as emptyTable for ActionUI (no separate "remove without reload" distinction)
    OMCActionUIClearControlRows(mOMCDialogProxy->GetDialogUUID(), (__bridge CFStringRef)inControlID);
}

- (void)setTableRows:(CFArrayRef)rows forControlID:(NSString *)inControlID
{
    OMCActionUISetControlTableRows(mOMCDialogProxy->GetDialogUUID(), (__bridge CFStringRef)inControlID, rows);
}

- (void)addTableRows:(CFArrayRef)rows forControlID:(NSString *)inControlID
{
    OMCActionUIAppendControlTableRows(mOMCDialogProxy->GetDialogUUID(), (__bridge CFStringRef)inControlID, rows);
}

- (void)setTableColumns:(CFArrayRef)columns forControlID:(NSString *)inControlID
{
    OMCActionUISetControlTableColumns(mOMCDialogProxy->GetDialogUUID(), (__bridge CFStringRef)inControlID, columns);
}

#pragma mark - Table / List row selection

- (void)selectRow:(NSInteger)rowIndex forControlID:(NSString *)inControlID
{
    OMCActionUISelectControlRow(mOMCDialogProxy->GetDialogUUID(), (__bridge CFStringRef)inControlID, rowIndex);
}

- (void)selectRowWithContent:(NSString *)text column:(NSInteger)columnNumber forControlID:(NSString *)inControlID
{
    OMCActionUISelectControlRowWithContent(mOMCDialogProxy->GetDialogUUID(), (__bridge CFStringRef)inControlID, (__bridge CFStringRef)text, columnNumber);
}

- (void)deselectRowForControlID:(NSString *)inControlID
{
    OMCActionUIDeselectControlRow(mOMCDialogProxy->GetDialogUUID(), (__bridge CFStringRef)inControlID);
}

/// Where the document named by JSON_NAME or omc_present_modal is (OMCActionUIDocumentLookup.h): an
/// absolute path, else a resource of the command's bundle, the main bundle or OMC's framework
- (NSURL *)resolveJSONURL:(NSString *)resourceNameOrPath
{
    return (NSURL *)CFBridgingRelease(OMCCopyActionUIDocumentURL((__bridge CFStringRef)resourceNameOrPath,
                                                                 mExternBundleRef, mPlugin->GetBundleRef()));
}

#pragma mark - Modal presentation, toasts, alerts and confirmations (OMCActionUIControls.h)

- (void)presentModalWithResourceNameOrPath:(NSString *)resourceNameOrPath onDismissActionID:(NSString *)onDismissActionID
{
    if (resourceNameOrPath.length == 0)
        return;
    NSURL *jsonURL = [self resolveJSONURL:resourceNameOrPath];
    if (jsonURL == nil) {
        NSLog(@"[OMCActionUIWindowController] presentModal: cannot find JSON: %@", resourceNameOrPath);
        return;
    }
    OMCActionUIPresentModal(mOMCDialogProxy->GetDialogUUID(), (__bridge CFURLRef)jsonURL, (__bridge CFStringRef)onDismissActionID);
}

- (void)dismissModal
{
    OMCActionUIDismissModal(mOMCDialogProxy->GetDialogUUID());
}

- (void)presentToastWithMessage:(NSString *)message duration:(NSTimeInterval)duration actionTitle:(NSString *)actionTitle actionID:(NSString *)actionID
{
    OMCActionUIPresentToast(mOMCDialogProxy->GetDialogUUID(), (__bridge CFStringRef)message, duration,
                            (__bridge CFStringRef)actionTitle, (__bridge CFStringRef)actionID);
}

- (void)dismissToast
{
    OMCActionUIDismissToast(mOMCDialogProxy->GetDialogUUID());
}

- (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message buttonSpecs:(NSArray *)buttonSpecs
{
    OMCActionUIPresentAlert(mOMCDialogProxy->GetDialogUUID(), (__bridge CFStringRef)title, (__bridge CFStringRef)message, (__bridge CFArrayRef)buttonSpecs);
}

- (void)presentConfirmationDialogWithTitle:(NSString *)title message:(NSString *)message buttonSpecs:(NSArray *)buttonSpecs
{
    OMCActionUIPresentConfirmationDialog(mOMCDialogProxy->GetDialogUUID(), (__bridge CFStringRef)title, (__bridge CFStringRef)message, (__bridge CFArrayRef)buttonSpecs);
}

- (void)dismissDialog
{
    OMCActionUIDismissDialog(mOMCDialogProxy->GetDialogUUID());
}

#pragma mark - Runtime Structural Mutations (OMCActionUIControls.h)

- (void)insertElementWithParentID:(NSInteger)parentID json:(NSString *)json container:(NSString *)container positionString:(NSString *)positionStr
{
    OMCActionUIInsertElement(mOMCDialogProxy->GetDialogUUID(), parentID, (__bridge CFStringRef)json, (__bridge CFStringRef)container, (__bridge CFStringRef)positionStr);
}

- (void)insertElementRowWithParentID:(NSInteger)parentID json:(NSString *)json container:(NSString *)container positionString:(NSString *)positionStr
{
    OMCActionUIInsertElementRow(mOMCDialogProxy->GetDialogUUID(), parentID, (__bridge CFStringRef)json, (__bridge CFStringRef)container, (__bridge CFStringRef)positionStr);
}

- (void)removeElementWithViewID:(NSInteger)viewID
{
    OMCActionUIRemoveElement(mOMCDialogProxy->GetDialogUUID(), viewID);
}

- (void)setTableColumnWidths:(CFArrayRef)widths forControlID:(NSString *)inControlID
{
    OMCActionUISetControlTableColumnWidths(mOMCDialogProxy->GetDialogUUID(), (__bridge CFStringRef)inControlID, widths);
}

@end

#endif // CURRENT_OMC_VERSION >= 50000
