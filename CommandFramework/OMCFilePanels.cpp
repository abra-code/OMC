//
//  OMCFilePanels.cpp
//  Abracode
//
//  The engine's save and open panels (Platform/OMCFilePanels.h). Portable: a test launch answers
//  them from the test's queued answers (OMCTestHost.h), so a panel never waits for a person who is
//  not there; otherwise the platform shows its own.
//

#include "OMCFilePanels.h"
#include "OMCTestHost.h"

CFURLRef
OMCCreateCFURLFromSaveAsDialog( CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath, CFStringRef inIdentifier, CFStringRef inPrompt, CFArrayRef inAllowedContentTypes, UInt32 inAdditonalFlags )
{
	if(OMCTestHostIsActive())
		return OMCTestHostAnswerSavePanel(inClientName, inMessage, inDefaultName, inDefaultDirPath, inIdentifier, inPrompt, inAllowedContentTypes, inAdditonalFlags);
	return OMCPlatformRunSavePanel(inClientName, inMessage, inDefaultName, inDefaultDirPath, inIdentifier, inPrompt, inAllowedContentTypes, inAdditonalFlags);
}

CFArrayRef
OMCCreateCFURLsFromOpenDialog( CFStringRef inClientName, CFStringRef inMessage, CFStringRef inDefaultName, CFStringRef inDefaultDirPath, CFStringRef inIdentifier, CFStringRef inPrompt, CFArrayRef inAllowedContentTypes, UInt32 inAdditonalFlags )
{
	if(OMCTestHostIsActive())
		return OMCTestHostAnswerOpenPanel(inClientName, inMessage, inDefaultName, inDefaultDirPath, inIdentifier, inPrompt, inAllowedContentTypes, inAdditonalFlags);
	return OMCPlatformRunOpenPanel(inClientName, inMessage, inDefaultName, inDefaultDirPath, inIdentifier, inPrompt, inAllowedContentTypes, inAdditonalFlags);
}
