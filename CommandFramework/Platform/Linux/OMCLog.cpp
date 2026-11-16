//
//  OMCLog.cpp (Linux)
//  Abracode
//
//  The Linux implementation of Platform/OMCLog.h: one line to stderr, where a desktop session's
//  journal or the terminal that started the applet gets it. Not built yet: the Linux port has no
//  build.
//

#include "OMCLog.h"
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
		// One write for the whole line, so lines from other threads do not interleave within it
		size_t lineLength = (size_t)length;
		if( (lineLength == 0) || (message[lineLength - 1] != '\n') )
		{
			message.back() = '\n';
			lineLength++;
		}
		(void)fwrite(message.data(), 1, lineLength, stderr);
	}
	va_end(arguments);
}
