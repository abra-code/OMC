#pragma once

#include "CFObj.h"

class OnMyCommandCM;
class CommandRuntimeData;

UInt32 GetNavDialogParams(CFDictionaryRef inFileDialogDict,
                          CFStringRef &outMessage,
                          CFArrayRef &outDefaultName,
                          CFArrayRef &outDefaultLocation,
                          CFStringRef &outIdentifier,
                          CFStringRef &outPrompt,
                          CFArrayRef &outAllowedContentTypes);

// The same with pointers, for Objective-C++ callers (OMCCommandExecutor.mm). Parses the shared
// options of a dialog settings dictionary (CHOOSE_FILE_DIALOG, OPEN_OBJECT_DIALOG, etc.) and returns
// the additional kOMCFilePanel* flags (OMCFilePanels.h). outAllowedContentTypes: array of UTI strings
// (e.g. "public.image", "public.audio") or NULL. Each out value is retained (caller releases).
UInt32 CopyNavDialogParams(CFDictionaryRef inParams, CFStringRef *outMessage, CFArrayRef *outDefaultName,
                           CFArrayRef *outDefaultLocation, CFStringRef *outIdentifier, CFStringRef *outPrompt,
                           CFArrayRef *outAllowedContentTypes);

void
PresentSaveAsDialog(OnMyCommandCM *inPlugin,
                    CommandRuntimeData &commandRuntimeData,
                    CFStringRef commandName,
                    CFBundleRef localizationBundle);

void
PresentChooseFileDialog(OnMyCommandCM *inPlugin,
                        CommandRuntimeData &commandRuntimeData,
                        CFStringRef commandName,
                        CFBundleRef localizationBundle);

void
PresentChooseFolderDialog(OnMyCommandCM *inPlugin,
                          CommandRuntimeData &commandRuntimeData,
                          CFStringRef commandName,
                          CFBundleRef localizationBundle);

void
PresentChooseObjectDialog(OnMyCommandCM *inPlugin,
                          CommandRuntimeData &commandRuntimeData,
                          CFStringRef commandName,
                          CFBundleRef localizationBundle);
