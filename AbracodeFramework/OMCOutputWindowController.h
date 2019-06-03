//
//  OMCOutputWindowController.h
//  Abracode
//
//  Created by Tomasz Kukielka on 5/14/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//

class OutputWindowHandler;
struct OutputWindowSettings;

#ifdef __OBJC__

#import <Cocoa/Cocoa.h>

@interface OMCOutputWindowController : NSWindowController
{
	IBOutlet NSTextView*	textView;
	OutputWindowHandler *	mHandler;//to delete when window closed
}

- (void)setup: (const OutputWindowSettings *)inSettings withHandler:(OutputWindowHandler *)inHandler;
- (void)setWindowPosition:(NSWindow *)inWindow withSettings: (const OutputWindowSettings *)inSettings;
- (void)setText:(NSString *)inText;
- (void)appendText:(NSString *)inText;

@end

#endif //__OBJC__

typedef void *OMCOutputWindowControllerRef;

OMCOutputWindowControllerRef CreateOutputWindowController(const OutputWindowSettings &inSettings, OutputWindowHandler *inHandler);
void ReleaseOutputWindowController(OMCOutputWindowControllerRef inControllerRef);
void OMCOutputWindowSetText(OMCOutputWindowControllerRef inControllerRef, CFStringRef inText);
void OMCOutputWindowAppendText(OMCOutputWindowControllerRef inControllerRef, CFStringRef inText);
void OMCOutputWindowScheduleClosing(OMCOutputWindowControllerRef inControllerRef, CFTimeInterval delay);
void ResetOutputWindowCascading();

