//#include "OMCConstants.h"

#pragma once

enum
{
	kExecSilentPOpen,
	kExecSilentSystem,
	kExecTerminal,
	kExecITerm,
	kExecPOpenWithOutputWindow,
	kExecAppleScript,
	kExecAppleScriptWithOutputWindow,
	kExecShellScript,
	kExecShellScriptWithOutputWindow
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
	kMulObjProcessSeparately,
	kMulObjProcessTogether
};

enum
{
	kSortMethodNone,
	kSortMethodByName
};

enum
{
	kInputClearText,
	kInputPasswordText,
	kInputPopupMenu,
	kInputComboBox
};

enum
{
	kMatchExact,
	kMatchContains,
	kMatchRegularExpression
};

enum
{
	kMatchFileName,
	kMatchFilePath
};
