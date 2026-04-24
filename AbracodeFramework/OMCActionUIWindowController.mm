//
//  OMCActionUIWindowController.mm
//  Abracode
//
//  Created by Tomasz Kukielka on 2/17/26.
//  Copyright 2026 Abracode. All rights reserved.
//

#import "OMCActionUIWindowController.h"
#import "OMCActionUIDialog.h"
#import "OMCControlAccessor.h"
#include "OnMyCommand.h"
#include "CommandRuntimeData.h"
#include "ACFDict.h"
#include "OMCStrings.h"

// enable only in OMC version 5.0 or later
#if CURRENT_OMC_VERSION >= 50000
@import ActionUIObjCAdapter;

/// Returns YES if the string's first character suggests it could be a JSON fragment.
/// Mirrors JSONHelper.looksLikeJSONFragment in Swift — avoids NSJSONSerialization overhead
/// for plain strings, which are the most common case.
static BOOL LooksLikeJSONFragment(NSString *s)
{
    if (s.length == 0) return NO;
    unichar first = [s characterAtIndex:0];
    switch (first) {
        case '{': case '[':           // object, array
        case '"':                     // quoted string fragment
        case 't': case 'f': case 'n': // true, false, null
            return YES;
        default:
            return (first >= '0' && first <= '9') || first == '-'; // number
    }
}

/// Parses a string as JSON if it looks like a JSON fragment; otherwise returns the string as-is.
/// Falls back to the original string if JSON parsing fails.
static id ParseStringOrJSON(NSString *value)
{
    if (!LooksLikeJSONFragment(value))
        return value;
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil)
        return value;
    NSError *error = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data
                                               options:NSJSONReadingAllowFragments
                                                 error:&error];
    return (error == nil && parsed != nil) ? parsed : value;
}

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

/// Parses an array of "title:role:actionID" button spec strings into ActionUIObjCDialogButton objects.
/// Role field: "cancel": cancel, "destructive": destructive, anything else: default.
/// actionID field: empty string or missing = nil (no action fired on tap).
static NSArray<ActionUIObjCDialogButton *> *OMCParseButtonSpecs(NSArray *specs)
{
    NSMutableArray<ActionUIObjCDialogButton *> *buttons = [NSMutableArray array];
    for (NSString *spec in specs) {
        if (![spec isKindOfClass:[NSString class]]) continue;
        NSArray<NSString *> *parts = [spec componentsSeparatedByString:@":"];
        NSString *btnTitle = (parts.count >= 1) ? parts[0] : @"";
        if (btnTitle.length == 0) continue;
        NSString *roleStr  = (parts.count >= 2) ? parts[1] : @"";
        NSString *actionID = (parts.count >= 3 && parts[2].length > 0) ? parts[2] : nil;
        ActionUIObjCButtonRole role;
        if ([roleStr isEqualToString:@"cancel"])
            role = ActionUIObjCButtonRoleCancel;
        else if ([roleStr isEqualToString:@"destructive"])
            role = ActionUIObjCButtonRoleDestructive;
        else
            role = ActionUIObjCButtonRoleDefault;
        [buttons addObject:[[ActionUIObjCDialogButton alloc] initWithTitle:(NSString *)btnTitle
                                                                      role:role
                                                                  actionID:(NSString *)actionID]];
    }
    return buttons;
}

@implementation OMCActionUIWindowController

- (id)initWithOmc:(OnMyCommandCM *)inOmc commandRuntimeData:(CommandRuntimeData *)inCommandRuntimeData
{
   self = [super initWithOmc:inOmc commandRuntimeData:inCommandRuntimeData];
	if(self == nil)
		return nil;
    
    mOMCDialogProxy.Adopt( new OMCActionUIDialog() );
    mOMCDialogProxy->SetControlAccessor((__bridge void *)self);
    self->mCommandRuntimeData->SetAssociatedDialogUUID(mOMCDialogProxy->GetDialogUUID());

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

    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    self.hostingController = [ActionUIObjC loadHostingControllerWithURL:jsonURL
                                                                 windowUUID:windowUUID
                                                              isContentView:YES];
    if (self.hostingController == nil)
    {
        NSLog(@"Unable to create a view from ActionUI JSON file: %@", dialogJsonName);
        return self;
    }
    
    // Determine window style and class based on WINDOW_TYPE
    NSWindowStyleMask styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable;
    BOOL usePanel = NO;
    NSWindowLevel windowLevel = NSNormalWindowLevel;

    if(windowType != nullptr)
    {
        if( kCFCompareEqualTo == ::CFStringCompare( windowType, CFSTR("floating"), 0 ) )
        {
            styleMask |= NSWindowStyleMaskUtilityWindow;
            usePanel = YES;
            windowLevel = NSFloatingWindowLevel;
        }
        else if( kCFCompareEqualTo == ::CFStringCompare( windowType, CFSTR("global_floating"), 0 ) )
        {
            styleMask |= NSWindowStyleMaskUtilityWindow;
            usePanel = YES;
            windowLevel = kCGUtilityWindowLevel;
        }
        // "regular" is the default, no changes needed
    }

    NSWindow *window;
    if(usePanel)
    {
        NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 480, 320)
                                                    styleMask:styleMask
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
        [panel setFloatingPanel:YES];
        if(windowLevel == kCGUtilityWindowLevel)
            [panel setHidesOnDeactivate:NO];
        window = panel;
    }
    else
    {
        window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 320)
                                             styleMask:styleMask
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    }

    if(windowLevel != NSNormalWindowLevel)
        [window setLevel:windowLevel];

    [window setReleasedWhenClosed:NO];
    [window setContentView:self.hostingController.view];

    // Autosave name: if a saved frame exists it overrides the fitting size above.
    NSString *autosaveName = [NSString stringWithFormat:@"OMC.%@", dialogJsonName];
    [window setFrameAutosaveName:autosaveName];

    BOOL frameRestored = [window setFrameUsingName:autosaveName];
    if(!frameRestored)
    {
        // First launch — no saved frame yet, use fitting size and center
        // view.fitting size contains ideal size for the content view
       NSSize fittingSize = self.hostingController.view.fittingSize;
        if(fittingSize.width > 10 && fittingSize.height > 10)
            [window setContentSize:fittingSize];
        [window center];
    }

    [window setDelegate:self];
    self.window = window;

    // Set window title: WINDOW_TITLE param > associated file > dynamic command name
    if(windowTitle != nullptr)
    {
        [window setTitle:(__bridge NSString *)(CFStringRef)windowTitle];
    }
    else
    {
        OneObjProperties *associatedObj = mCommandRuntimeData->GetAssociatedObject();
        if(associatedObj != nullptr)
        {
            CFURLRef fileURL = associatedObj->url.Get();
            if(fileURL != NULL)
            {
                NSURL *associatedFileURL = (__bridge NSURL *)fileURL;
                window.representedURL = associatedFileURL;
                [window setTitleWithRepresentedFilename:associatedFileURL.path];
                [NSDocumentController.sharedDocumentController noteNewRecentDocumentURL:associatedFileURL];
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
            [window setTitle:(__bridge NSString *)(CFStringRef)dynamicCommandName];
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


- (void)dealloc
{
    OMCActionUIDialog *actionUIDialog = (OMCActionUIDialog *)mOMCDialogProxy.Get();
    if(actionUIDialog != nullptr)
        actionUIDialog->SetControlAccessor(nil);

    [self.window setDelegate:nil];
    // hostingController released by property, taking SwiftUI view hierarchy with it
}

#pragma mark - OMCControlAccessor protocol

- (void)setControlStringValue:(NSString *)inValue forControlID:(NSString *)inControlID contentType:(NSString *)contentType
{
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if(windowUUID == nil || inValue == nil || inControlID == nil)
        return;

    NSInteger viewID = [inControlID integerValue];
    [ActionUIObjC setElementValueFromStringWithWindowUUID:windowUUID viewID:viewID viewPartID:0 value:inValue contentType:contentType];
}

- (void)setControlEnabled:(BOOL)enabled forControlID:(NSString *)inControlID
{
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if (windowUUID == nil || inControlID == nil) return;
    NSInteger viewID = [inControlID integerValue];
    [ActionUIObjC setElementPropertyWithWindowUUID:windowUUID viewID:viewID propertyName:@"disabled" value:@(!enabled)];
}

- (void)setControlVisible:(BOOL)visible forControlID:(NSString *)inControlID
{
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if (windowUUID == nil || inControlID == nil) return;
    NSInteger viewID = [inControlID integerValue];
    [ActionUIObjC setElementPropertyWithWindowUUID:windowUUID viewID:viewID propertyName:@"hidden" value:@(!visible)];
}

- (void)setPropertyKey:(NSString *)propertyKey jsonValue:(NSString *)jsonValue forControlID:(NSString *)inControlID
{
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if (windowUUID == nil || inControlID == nil || propertyKey == nil || jsonValue == nil)
        return;
    NSInteger viewID = [inControlID integerValue];
    id parsedValue = ParseStringOrJSON(jsonValue);
    [ActionUIObjC setElementPropertyWithWindowUUID:windowUUID viewID:viewID propertyName:propertyKey value:parsedValue];
}

- (void)setStateKey:(NSString *)stateKey stringOrJsonValue:(NSString *)value forControlID:(NSString *)inControlID
{
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if (windowUUID == nil || inControlID == nil || stateKey == nil || value == nil)
        return;
    NSInteger viewID = [inControlID integerValue];
    id parsedValue = ParseStringOrJSON(value);
    [ActionUIObjC setElementStateWithWindowUUID:windowUUID viewID:viewID key:stateKey value:parsedValue];
}

#pragma mark - List controls

- (void)removeAllListItemsForControlID:(NSString *)inControlID
{
    // List items are stored as single-column rows in states["content"]
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if (windowUUID == nil || inControlID == nil) return;
    NSInteger viewID = [inControlID integerValue];
    [ActionUIObjC clearElementRowsWithWindowUUID:windowUUID viewID:viewID];
}

- (void)setListItems:(CFArrayRef)items forControlID:(NSString *)inControlID
{
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if (windowUUID == nil || inControlID == nil) return;
    NSInteger viewID = [inControlID integerValue];
    CFIndex count = (items != NULL) ? CFArrayGetCount(items) : 0;
    NSMutableArray<NSArray<NSString*>*> *rows = [NSMutableArray arrayWithCapacity:count];
    for (CFIndex i = 0; i < count; i++) {
        CFStringRef item = (CFStringRef)CFArrayGetValueAtIndex(items, i);
        if (item != NULL)
            [rows addObject:@[(__bridge NSString *)item]];
    }
    [ActionUIObjC setElementRowsWithWindowUUID:windowUUID viewID:viewID rows:rows];
}

- (void)appendListItems:(CFArrayRef)items forControlID:(NSString *)inControlID
{
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if (windowUUID == nil || inControlID == nil) return;
    NSInteger viewID = [inControlID integerValue];
    CFIndex count = (items != NULL) ? CFArrayGetCount(items) : 0;
    NSMutableArray<NSArray<NSString*>*> *rows = [NSMutableArray arrayWithCapacity:count];
    for (CFIndex i = 0; i < count; i++) {
        CFStringRef item = (CFStringRef)CFArrayGetValueAtIndex(items, i);
        if (item != NULL)
            [rows addObject:@[(__bridge NSString *)item]];
    }
    if (rows.count > 0)
        [ActionUIObjC appendElementRowsWithWindowUUID:windowUUID viewID:viewID rows:rows];
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

/// Converts a CFArrayRef of tab-separated row strings into NSArray<NSArray<NSString*>*>.
static NSArray<NSArray<NSString*>*> *OMCParseTabSeparatedRows(CFArrayRef cfRows)
{
    CFIndex count = (cfRows != NULL) ? CFArrayGetCount(cfRows) : 0;
    NSMutableArray<NSArray<NSString*>*> *result = [NSMutableArray arrayWithCapacity:count];
    for (CFIndex i = 0; i < count; i++) {
        CFStringRef rowCFStr = (CFStringRef)CFArrayGetValueAtIndex(cfRows, i);
        NSString *rowStr = (__bridge NSString *)rowCFStr;
        [result addObject:[rowStr componentsSeparatedByString:@"\t"]];
    }
    return result;
}

- (void)emptyTableForControlID:(NSString *)inControlID
{
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if (windowUUID == nil || inControlID == nil) return;
    NSInteger viewID = [inControlID integerValue];
    [ActionUIObjC clearElementRowsWithWindowUUID:windowUUID viewID:viewID];
}

- (void)removeTableRowsForControlID:(NSString *)inControlID
{
    // Same as emptyTable for ActionUI (no separate "remove without reload" distinction)
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if (windowUUID == nil || inControlID == nil) return;
    NSInteger viewID = [inControlID integerValue];
    [ActionUIObjC clearElementRowsWithWindowUUID:windowUUID viewID:viewID];
}

- (void)setTableRows:(CFArrayRef)rows forControlID:(NSString *)inControlID
{
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if (windowUUID == nil || inControlID == nil) return;
    NSInteger viewID = [inControlID integerValue];
    NSArray<NSArray<NSString*>*> *parsedRows = OMCParseTabSeparatedRows(rows);
    [ActionUIObjC setElementRowsWithWindowUUID:windowUUID viewID:viewID rows:parsedRows ?: @[]];
}

- (void)addTableRows:(CFArrayRef)rows forControlID:(NSString *)inControlID
{
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if (windowUUID == nil || inControlID == nil) return;
    NSInteger viewID = [inControlID integerValue];
    NSArray<NSArray<NSString*>*> *parsedRows = OMCParseTabSeparatedRows(rows);
    if (parsedRows.count > 0)
        [ActionUIObjC appendElementRowsWithWindowUUID:windowUUID viewID:viewID rows:parsedRows];
}

- (void)setTableColumns:(CFArrayRef)columns forControlID:(NSString *)inControlID
{
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if (windowUUID == nil || inControlID == nil) return;
    NSInteger viewID = [inControlID integerValue];
    CFIndex count = (columns != NULL) ? CFArrayGetCount(columns) : 0;
    NSMutableArray<NSString*> *names = [NSMutableArray arrayWithCapacity:count];
    for (CFIndex i = 0; i < count; i++) {
        CFStringRef name = (CFStringRef)CFArrayGetValueAtIndex(columns, i);
        [names addObject:(__bridge NSString *)name];
    }
    [ActionUIObjC setElementPropertyWithWindowUUID:windowUUID viewID:viewID propertyName:@"columns" value:names];
}

/// Resolves a resource name or absolute path to a file URL.
/// Searches the same bundle chain used for the main dialog JSON (external bundle > main bundle > framework bundle).
- (NSURL *)resolveJSONURL:(NSString *)resourceNameOrPath
{
    if (resourceNameOrPath.length == 0) return nil;

    // Absolute path: use directly
    if ([resourceNameOrPath hasPrefix:@"/"])
        return [NSURL fileURLWithPath:resourceNameOrPath];

    // Strip .json extension for resource lookup if present
    NSString *baseName = [resourceNameOrPath hasSuffix:@".json"]
        ? [resourceNameOrPath stringByDeletingPathExtension]
        : resourceNameOrPath;

    if (mExternBundleRef != NULL) {
        CFObj<CFURLRef> bundleURL( CFBundleCopyBundleURL(mExternBundleRef) );
        if (bundleURL != NULL) {
            CFObj<CFStringRef> bundlePath = CreatePathFromCFURL(bundleURL, kEscapeNone);
            if (bundlePath != nullptr) {
                NSBundle *externBundle = [NSBundle bundleWithPath:(__bridge NSString *)bundlePath.Get()];
                NSString *jsonPath = [externBundle pathForResource:baseName ofType:@"json"];
                if (jsonPath != nil)
                    return [NSURL fileURLWithPath:jsonPath];
            }
        }
    }

    NSString *jsonPath = [[NSBundle mainBundle] pathForResource:baseName ofType:@"json"];
    if (jsonPath != nil)
        return [NSURL fileURLWithPath:jsonPath];

    CFBundleRef frameworkBundleRef = mPlugin->GetBundleRef();
    if (frameworkBundleRef != NULL) {
        CFObj<CFURLRef> bundleURL( CFBundleCopyBundleURL(frameworkBundleRef) );
        if (bundleURL != NULL) {
            CFObj<CFStringRef> bundlePath = CreatePathFromCFURL(bundleURL, kEscapeNone);
            if (bundlePath != nullptr) {
                NSBundle *omcBundle = [NSBundle bundleWithPath:(__bridge NSString *)bundlePath.Get()];
                NSString *path = [omcBundle pathForResource:baseName ofType:@"json"];
                if (path != nil) return [NSURL fileURLWithPath:path];
            }
        }
    }

    return nil;
}

#pragma mark - Modal presentation (ActionUI)

- (void)presentModalWithResourceNameOrPath:(NSString *)resourceNameOrPath onDismissActionID:(NSString *)onDismissActionID
{
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if (windowUUID == nil || resourceNameOrPath.length == 0)
        return;

    NSURL *jsonURL = [self resolveJSONURL:resourceNameOrPath];
    if (jsonURL == nil) {
        NSLog(@"[OMCActionUIWindowController] presentModal: cannot find JSON: %@", resourceNameOrPath);
        return;
    }
    NSData *data = [NSData dataWithContentsOfURL:jsonURL];
    if (data == nil) {
        NSLog(@"[OMCActionUIWindowController] presentModal: cannot read JSON at: %@", jsonURL);
        return;
    }

    NSError *error = nil;
    BOOL success = [ActionUIObjC presentModalWithWindowUUID:windowUUID
                                        data:(NSData *)data
                                      format:@"json"
                                       style:ActionUIObjCModalStyleSheet
                          onDismissActionID:onDismissActionID
                                       error:&error];
    if (!success && (error != nil))
        NSLog(@"[OMCActionUIWindowController] presentModal error: %@", error);
}

- (void)dismissModal
{
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if (windowUUID != nil)
        [ActionUIObjC dismissModalWithWindowUUID:windowUUID];
}

- (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message buttonSpecs:(NSArray *)buttonSpecs
{
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if (windowUUID == nil || title.length == 0)
        return;
    NSArray<ActionUIObjCDialogButton *> *buttons = OMCParseButtonSpecs(buttonSpecs);
    NSString *msg = (message.length > 0) ? message : nil;
    if (buttons.count > 0)
        [ActionUIObjC presentAlertWithWindowUUID:windowUUID title:title message:msg buttons:buttons];
    else
        [ActionUIObjC presentAlertWithWindowUUID:windowUUID title:title message:msg buttons:nil];
}

- (void)presentConfirmationDialogWithTitle:(NSString *)title message:(NSString *)message buttonSpecs:(NSArray *)buttonSpecs
{
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if (windowUUID == nil || title.length == 0)
        return;
    NSArray<ActionUIObjCDialogButton *> *buttons = OMCParseButtonSpecs(buttonSpecs);
    NSString *msg = (message.length > 0) ? message : nil;
    [ActionUIObjC presentConfirmationDialogWithWindowUUID:windowUUID title:title message:msg buttons:(NSArray *)buttons];
}

- (void)dismissDialog
{
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if (windowUUID != nil)
        [ActionUIObjC dismissDialogWithWindowUUID:windowUUID];
}

- (void)setTableColumnWidths:(CFArrayRef)widths forControlID:(NSString *)inControlID
{
    NSString *windowUUID = (__bridge NSString *)mOMCDialogProxy->GetDialogUUID();
    if (windowUUID == nil || inControlID == nil)
        return;
    NSInteger viewID = [inControlID integerValue];
    CFIndex count = (widths != NULL) ? CFArrayGetCount(widths) : 0;
    NSMutableArray<NSNumber*> *widthNumbers = [NSMutableArray arrayWithCapacity:count];
    for (CFIndex i = 0; i < count; i++) {
        CFTypeRef item = CFArrayGetValueAtIndex(widths, i);
        if (CFGetTypeID(item) == CFNumberGetTypeID()) {
            double val = 0;
            CFNumberGetValue((CFNumberRef)item, kCFNumberDoubleType, &val);
            [widthNumbers addObject:@(val)];
        } else if (CFGetTypeID(item) == CFStringGetTypeID()) {
            double val = [(__bridge NSString *)item doubleValue];
            [widthNumbers addObject:@(val)];
        }
    }
    [ActionUIObjC setElementPropertyWithWindowUUID:windowUUID viewID:viewID propertyName:@"widths" value:widthNumbers];
}

@end

#endif // CURRENT_OMC_VERSION >= 50000
