//#include "OMCConstants.h"

#pragma once

enum
{
	kExecSilentPOpen = 0,
	kExecSilentSystem,
	kExecTerminal,
	kExecITerm,
	kExecPOpenWithOutputWindow,
	kExecAppleScript,
	kExecAppleScriptWithOutputWindow,
	kExecPopenScriptFile,
	kExecPopenScriptFileWithOutputWindow
};


enum
{
	kEscapeModeFirst = 0,
	kEscapeNone = kEscapeModeFirst,
	kEscapeWithBackslash,
	kEscapeWithPercent,
	kEscapeWithPercentAll,
	kEscapeForAppleScript,
	kEscapeWrapWithSingleQuotesForShell,
	kEscapeModeLast = kEscapeWrapWithSingleQuotesForShell
};

enum
{
	kMulObjProcessSeparately = 0,
	kMulObjProcessTogether
};

enum
{
	kSortMethodNone = 0,
	kSortMethodByName
};

enum
{
    kInputNone = 0,
	kInputClearText,
	kInputPasswordText,
	kInputPopupMenu,
	kInputComboBox
};

enum
{
	kMatchExact = 0,
	kMatchContains,
	kMatchRegularExpression
};

enum
{
	kMatchFileName = 0,
	kMatchFilePath
};
