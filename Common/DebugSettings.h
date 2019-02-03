//**************************************************************************************// Filename:	DebugSettings.h//				Part of Contextual Menu Workshop by Abracode Inc.//				http://free.abracode.com/cmworkshop/// Copyright � 2003 Abracode, Inc.  All rights reserved.//// Description:	////**************************************************************************************// Revision History:// Friday, March 7, 2003 - Original//**************************************************************************************#pragma once#ifndef _DEBUG_	#define _DEBUG_		0#endif#ifndef _TRACE_	#define _TRACE_		0#endif//open "Console" app to check for debugging strings#if (_DEBUG_ == 1)	#define DEBUG_PSTR(_iPStr)		DebugStr(_iPStr)	#define DEBUG_CFSTR(_iCFStr)	CFShow(_iCFStr)	#define DEBUG_CSTR				printf	#define DEBUG_CSTR1(_inCStr)	CFShow(CFSTR(_inCStr))#else	#define DEBUG_PSTR(_iPStr)	#define DEBUG_CFSTR(_iCFStr)	#define DEBUG_CSTR(...)	#define DEBUG_CSTR1(_inCStr)#endif //(_DEBUG_ == 1)//TRACE_PSTR is useful for tracing which functions are called and when//you do not need it when everything goes well,//but when you do not know what is going on it can be very helpful#if (_TRACE_ == 1)	#define TRACE_PSTR(_iPStr)		DebugStr(_iPStr)	#define TRACE_CFSTR(_iCFStr)	CFShow(_iCFStr)	#define TRACE_CSTR				printf	#define TRACE_CSTR1(_inCStr)	CFShow(CFSTR(_inCStr))#else	#define TRACE_PSTR(_iPStr)	#define TRACE_CFSTR(_iCFStr)	#define TRACE_CSTR(...)	#define TRACE_CSTR1(_inCStr)#endif //(_DEBUG_ == 1)//error logging, always outputs to console#define LOG_PSTR(_iPStr)	DebugStr(_iPStr)#define LOG_CFSTR(_iCFStr)	CFShow(_iCFStr)#define LOG_CSTR			printf#define LOG_CSTR1(_inCStr)	CFShow(CFSTR(_inCStr))