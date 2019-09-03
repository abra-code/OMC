/*
	OMCPDFView.m
*/

#import "OMCPDFView.h"

@implementation OMCPDFView

@synthesize tag;
@synthesize escapingMode;

- (id)init
{
    self = [super init];
	if(self == NULL)
		return NULL;
	self.escapingMode = @"esc_none";
	return self;
}

- (void)dealloc
{
	[escapingMode release];
    [super dealloc];
}

//legacy encoder/decoder support - custom control data no longer serialized into nibs
//custom properties get set later on nib load by calling proprty setters

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
	if(self == nil)
		return nil;

	self.escapingMode = @"esc_none";

    return self;
}

- (NSString *)stringValue
{
	PDFDocument *pdfDoc = [self document];
	if(pdfDoc == nil)
		return nil;

	NSURL *pdfURL = [pdfDoc documentURL];
	if(pdfURL == nil)
		return nil;

	return [pdfURL path];
}

- (void)setStringValue:(NSString *)aString
{
	if(aString == nil)
		return;

	NSURL *pdfURL = [NSURL fileURLWithPath:aString];
	if(pdfURL == nil)
		return;

	PDFDocument *pdfDoc = [[PDFDocument alloc] initWithURL:pdfURL];
	if(pdfDoc == nil)
		return;

	[self setDocument:pdfDoc];
	
	[pdfDoc release];
}


@end
