//
//  OMCDropletController.m
//  CocoaApp
//
//  Created by Tomasz Kukielka on 4/17/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//

#import "OMCDropletController.h"
#import "OMCCommandExecutor.h"
#include "OMCWindowHost.h"
#include "CFObj.h"
#include "OMCFilePanels.h"
#include "OMC.h"
#import "OMCService.h"
#include "OMCHostInfo.h"
#include "OMCApplet.h"
#include <memory>


static OMCService *sOMCService = NULL;

// The applet's decisions are portable (OMCApplet.h); these are what only macOS does for them.
// inActionContext is the controller, which owns the OMCApplet and so outlives every call.

static OSStatus AppletRunMainCommand(void *inActionContext, CFTypeRef inContext)
{
	OMCDropletController *controller = (__bridge OMCDropletController *)inActionContext;
	return [OMCCommandExecutor runCommand:controller.commandID forCommandFile:controller.commandFilePath withContext:(__bridge id)inContext useNavDialog:YES allowKeyWindowSubcommand:NO delegate:controller];
}

static void AppletRunURL(void *inActionContext, CFStringRef inURL)
{
	OMCDropletController *controller = (__bridge OMCDropletController *)inActionContext;
	OSStatus err = [OMCCommandExecutor runCommandForURL:(__bridge NSString *)inURL forCommandFile:controller.commandFilePath delegate:controller];
	(void)err;
}

static void AppletNoteRecentDocument(void *inActionContext, CFURLRef inFileURL)
{
	(void)inActionContext;
	OMCNoteRecentDocumentURL((__bridge NSURL *)inFileURL);
}

@interface OMCDropletController ()
{
	std::unique_ptr<OMCApplet> _applet;
}
// The application that last asked to open files: told when they were opened
@property (nonatomic, strong) NSApplication *openingApplication;
- (void)didOpenGatheredFiles;
@end

static void AppletDidOpenGatheredFiles(void *inActionContext)
{
	OMCDropletController *controller = (__bridge OMCDropletController *)inActionContext;
	[controller didOpenGatheredFiles];
}

static std::unique_ptr<OMCApplet> CreateApplet(OMCDropletController *inController)
{
	OMCAppletActions actions;
	actions.runMainCommand = AppletRunMainCommand;
	actions.runURL = AppletRunURL;
	actions.noteRecentDocument = AppletNoteRecentDocument;
	actions.didOpenGatheredFiles = AppletDidOpenGatheredFiles;
	actions.context = (__bridge void *)inController;
	return std::unique_ptr<OMCApplet>(new OMCApplet(actions));
}

@implementation OMCDropletController

- (id)init
{
	self = [super init];
	if(self == nil)
		return nil;

	_commandFilePath = @"Command.plist";
	_applet = CreateApplet(self);
	
	NSAppleEventManager *eventManager = [NSAppleEventManager sharedAppleEventManager];
	[eventManager setEventHandler:self
					andSelector:@selector(handleGetURLEvent:withReplyEvent:)
					forEventClass:kInternetEventClass
					andEventID:kAEGetURL];

	return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
	if(self == nil)
		return nil;

	_commandFilePath = @"Command.plist";
	_applet = CreateApplet(self);
	
	NSAppleEventManager *eventManager = [NSAppleEventManager sharedAppleEventManager];
	[eventManager setEventHandler:self
					andSelector:@selector(handleGetURLEvent:withReplyEvent:)
					forEventClass:kInternetEventClass
					andEventID:kAEGetURL];

    return self;
}

- (void)awakeFromNib
{
//	NSLog( @"OMCDropletController awakeFromNib " );

	NSApplication *myApp = [NSApplication sharedApplication];
	if(myApp != NULL)
	{
		[myApp setDelegate:self];
		//NSEvent *currEvent = [myApp currentEvent];
		//if(currEvent)
		//	_startupModifiers = [currEvent modifierFlags];
	}

	_applet->SetStartupModifiers(OMCGetKeyboardModifiers());
}

- (void)openDocumentWithContentsOfURL:(NSURL *)absoluteURL display:(BOOL)displayDocument completionHandler:(void (^)(NSDocument * _Nullable document, BOOL documentWasAlreadyOpen, NSError * _Nullable error))completionHandler
{
	_applet->OpenFile((__bridge CFURLRef)absoluteURL);
	completionHandler(NULL, NO, NULL);
}


-(void)openFiles:(NSArray *)absoluteURLArray
{
	_applet->OpenFiles((__bridge CFArrayRef)absoluteURLArray);
}


- (IBAction)newDocument:(id)sender
{
	_applet->RunMainCommand();
}

- (IBAction)openDocument:(id)sender
{
	_applet->RunMainCommand();
}


//- (id)makeUntitledDocumentOfType:(NSString *)typeName error:(NSError **)outError
//{
//	return NULL;
//}

- (BOOL)validateUserInterfaceItem:(id < NSValidatedUserInterfaceItem >)anItem
{
	SEL actonSel = [anItem action];

//check if default command is file-based and enable openDocument
//if not, enable newDocument

	NSString* selectorStr = NSStringFromSelector( actonSel );
	if( [selectorStr isEqualToString: @"newDocument:"] )
		return YES;

	if( [selectorStr isEqualToString: @"openDocument:"] )
		return YES;

//	const char* actionName = sel_getName(actonSel);
//	printf(actionName); printf("\n");
	return [super validateUserInterfaceItem:anItem];
}

#pragma mark --- Open Recent menu (programmatic population) ---

- (void)installOpenRecentMenu
{
	NSMenu *mainMenu = [NSApp mainMenu];
	if(mainMenu == nil)
		return;

	// The shared programmatic menu bar (ActionUIMenuBar) does not include an
	// "Open Recent" submenu, because AppKit only auto-populates Open Recent for
	// nib-based menus. OMC builds it here and drives it manually via
	// -menuNeedsUpdate:. Locate the File menu by its "Open…" item and insert the
	// submenu just after it.
	for(NSMenuItem *topItem in mainMenu.itemArray)
	{
		NSMenu *fileMenu = topItem.submenu;
		if(fileMenu == nil)
			continue;

		NSInteger openIndex = [fileMenu indexOfItemWithTitle:@"Open…"];
		if(openIndex < 0)
			continue;

		// Don't insert twice if called more than once.
		if([fileMenu indexOfItemWithTitle:@"Open Recent"] >= 0)
			return;

		NSMenuItem *openRecentItem = [[NSMenuItem alloc] initWithTitle:@"Open Recent" action:NULL keyEquivalent:@""];
		NSMenu *openRecentMenu = [[NSMenu alloc] initWithTitle:@"Open Recent"];
		openRecentMenu.delegate = self;
		openRecentItem.submenu = openRecentMenu;
		[fileMenu insertItem:openRecentItem atIndex:(openIndex + 1)];
		return;
	}
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
	// Rebuild the Open Recent submenu from the shared document controller's
	// recent documents each time it is about to open.
	[menu removeAllItems];

	NSArray<NSURL *> *recentURLs = [NSDocumentController.sharedDocumentController recentDocumentURLs];
	NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
	NSFileManager *fileManager = [NSFileManager defaultManager];

	for(NSURL *url in recentURLs)
	{
		NSString *title = [fileManager displayNameAtPath:url.path];
		if(title.length == 0)
			title = url.lastPathComponent;

		NSMenuItem *item = [menu addItemWithTitle:title
										   action:@selector(omcOpenRecentDocument:)
									keyEquivalent:@""];
		item.target = self;
		item.representedObject = url;

		NSImage *icon = [workspace iconForFile:url.path];
		icon.size = NSMakeSize(16.0, 16.0);
		item.image = icon;
	}

	if(recentURLs.count > 0)
		[menu addItem:[NSMenuItem separatorItem]];

	// "Clear Menu" targets the first responder → the shared NSDocumentController.
	[menu addItemWithTitle:@"Clear Menu"
					action:@selector(clearRecentDocuments:)
			 keyEquivalent:@""];
}

- (void)omcOpenRecentDocument:(NSMenuItem *)sender
{
	NSURL *url = sender.representedObject;
	if(![url isKindOfClass:[NSURL class]])
		return;

	// OMCDropletController overrides -openDocumentWithContentsOfURL:display:completionHandler:
	// to run the applet's command with the file — the same path used for drops
	// and File ▸ Open….
	[NSDocumentController.sharedDocumentController
		openDocumentWithContentsOfURL:url
							  display:YES
					completionHandler:^(NSDocument *document, BOOL alreadyOpen, NSError *error) { }];
}

#pragma mark --- NSApplication delegate methods ---

- (void)application:(NSApplication *)sender openURLs:(NSArray<NSURL *> *)urls
{
	self.openingApplication = sender;
	_applet->OpenURLs((__bridge CFArrayRef)urls);
}

- (void)didOpenGatheredFiles
{
	[self.openingApplication replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)hasVisibleWindows
{
	long appWindowCount = (long)[[[NSApplication sharedApplication] windows] count];
	return _applet->ShouldHandleReopen(hasVisibleWindows, OMCOpenHostedWindowCount(), appWindowCount);
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)theApplication
{
	return _applet->OpenUntitled();
}

//Apple docs state:
// If the user started up the application by double-clicking a file,
// the delegate receives the application:openFile: message before receiving applicationDidFinishLaunching:
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	_applet->DidFinishLaunching();
	
	if(sOMCService == NULL)
	{
		NSBundle *appBundle = [NSBundle mainBundle];
		NSDictionary *infoDictionary = [appBundle infoDictionary];
		NSArray *servicesArray = (NSArray *)[infoDictionary objectForKey:@"NSServices"];
		if( (servicesArray != NULL) &&
			[servicesArray isKindOfClass:[NSArray class]] &&
			([servicesArray count] > 0) )
		{
			sOMCService = [[OMCService alloc] init];
			[sOMCService applicationDidFinishLaunching:aNotification];
		}
	}
}

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
    // Extract the URL from the Apple event and handle it here.
	 NSString* urlString = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
	 if(urlString == NULL)
		return;

	_applet->HandleURL((__bridge CFStringRef)urlString);
}

#pragma mark --- OMC support ---

- (void)setCommandFilePath:(NSString *)inPath
{
	if((inPath != nil) && ([inPath length] > 0))
	{
		_commandFilePath = inPath;
	}
	else
	{
		_commandFilePath = @"Command.plist";
	}
}

#pragma mark --- STUBS ---

- (void)addDocument:(NSDocument *)document
{
}

- (id)currentDocument
{
	return NULL;
}

- (NSString *)defaultType
{
	return NULL;
}

- (id)documentForURL:(NSURL *)absoluteURL
{
	return NULL;
}

- (id)documentForWindow:(NSWindow *)window
{
	return NULL;
}

- (NSArray *)documents
{	
	return [NSArray array];
}

- (BOOL)hasEditedDocuments
{
	return NO;
}

- (id)makeDocumentForURL:(NSURL *)absoluteDocumentURL withContentsOfURL:(NSURL *)absoluteDocumentContentsURL ofType:(NSString *)typeName error:(NSError **)outError
{
	if(outError != NULL)
		*outError = [NSError errorWithDomain:@"Not implemented" code:-1 userInfo:NULL];

	return NULL;
}

- (id)makeDocumentWithContentsOfURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
	if(outError != NULL)
		*outError = [NSError errorWithDomain:@"Not implemented" code:-1 userInfo:NULL];

	return NULL;
}

- (id)makeUntitledDocumentOfType:(NSString *)typeName error:(NSError **)outError
{
	if(outError != NULL)
		*outError = [NSError errorWithDomain:@"Not implemented" code:-1 userInfo:NULL];

	return NULL;
}

- (id)openUntitledDocumentAndDisplay:(BOOL)displayDocument error:(NSError **)outError
{
	if(outError != NULL)
		*outError = [NSError errorWithDomain:@"Not implemented" code:-1 userInfo:NULL];
	return NULL;
}

- (void)reopenDocumentForURL:(NSURL *)absoluteDocumentURL withContentsOfURL:(NSURL *)absoluteDocumentContentsURL display:(BOOL)displayDocument completionHandler:(void (^)(NSDocument * _Nullable document, BOOL documentWasAlreadyOpen, NSError * _Nullable error))completionHandler
{
	// OMC applets do not reopen documents. Override the modern (completion-handler) variant the same
	// way the deprecated reopenDocumentForURL:withContentsOfURL:error: override used to neutralize it,
	// so reopen/state-restoration never routes back into openDocument... and re-runs the command.
	NSError *notImplementedError = [NSError errorWithDomain:@"Not implemented" code:-1 userInfo:NULL];
	completionHandler(NULL, NO, notImplementedError);
}

- (void)reviewUnsavedDocumentsWithAlertTitle:(NSString *)title cancellable:(BOOL)cancellable delegate:(id)delegate didReviewAllSelector:(SEL)didReviewAllSelector contextInfo:(void *)contextInfo
{
}

- (IBAction)saveAllDocuments:(id)sender
{
}

@end
