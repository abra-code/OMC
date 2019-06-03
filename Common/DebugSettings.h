//**************************************************************************************
// Filename:	DebugSettings.h
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
// Copyright � 2003 Abracode, Inc.  All rights reserved.
//
// Description:	
//
//**************************************************************************************
// Revision History:
// Friday, March 7, 2003 - Original
//**************************************************************************************

#pragma once

#ifndef _DEBUG_
	#define _DEBUG_		0
#endif

#ifndef _TRACE_
	#define _TRACE_		0
#endif

#if (_DEBUG_ == 1)
	#define DEBUG_CFSTR(_iCFStr)	CFShow(_iCFStr)
	#define DEBUG_CSTR				printf
#else
	#define DEBUG_CFSTR(_iCFStr)
	#define DEBUG_CSTR(...)
#endif //(_DEBUG_ == 1)

#if (_TRACE_ == 1)
	#define TRACE_CFSTR(_iCFStr)	CFShow(_iCFStr)
	#define TRACE_CSTR				printf
#else
	#define TRACE_CFSTR(_iCFStr)
	#define TRACE_CSTR(...)
#endif //(_DEBUG_ == 1)

#define LOG_CFSTR(_iCFStr)	CFShow(_iCFStr)
#define LOG_CSTR			printf
