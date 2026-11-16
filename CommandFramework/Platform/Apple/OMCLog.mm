//
//  OMCLog.mm
//  Abracode
//
//  macOS implementation of Platform/OMCLog.h: NSLog, as the Objective-C code it serves used.
//

#include "OMCLog.h"
#import <Foundation/Foundation.h>
#include <stdarg.h>
#include <stdio.h>
#include <vector>

void OMCLogMessage(const char *inFormat, ...)
{
	va_list arguments;
	va_start(arguments, inFormat);
	va_list measuring;
	va_copy(measuring, arguments);
	int length = vsnprintf(NULL, 0, inFormat, measuring);
	va_end(measuring);
	if(length >= 0)
	{
		std::vector<char> message((size_t)length + 1);
		(void)vsnprintf(message.data(), message.size(), inFormat, arguments);
		// The message is UTF-8: NSLog's %s would read it in the system encoding (MacRoman) and
		// garble non-ASCII text, such as a command id, that the old %@ arguments logged intact.
		NSString *text = [NSString stringWithUTF8String:message.data()];
		if(text != nil)
			NSLog(@"%@", text);
		else
			NSLog(@"%s", message.data());
	}
	va_end(arguments);
}
