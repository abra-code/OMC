/*
	OMCPDFView.m
*/

#import "OMCPDFView.h"

@implementation OMCPDFView

@synthesize tag = _omcTag, escapingMode;

- (id)init
{
    self = [super init];
	if(self == NULL)
		return NULL;
    _omcTag = 0;
	escapingMode = @"esc_none";
	[escapingMode retain];
	return self;
}

- (void)dealloc
{
	[escapingMode release];
    [super dealloc];
}

- (NSString *)stringValue
{
	PDFDocument *pdfDoc = [self document];
	if(pdfDoc == NULL)
		return NULL;

	NSURL *pdfURL = [pdfDoc documentURL];
	if(pdfURL == NULL)
		return NULL;

	return [pdfURL path];
}

- (void)setStringValue:(NSString *)aString
{
	if(aString == NULL)
		return;

	NSURL *pdfURL = [NSURL fileURLWithPath:aString];
	if(pdfURL == NULL)
		return;

	PDFDocument *pdfDoc = [[PDFDocument alloc] initWithURL:pdfURL];
	if(pdfDoc == NULL)
		return;

	[self setDocument:pdfDoc];
	
	[pdfDoc release];
}


@end
