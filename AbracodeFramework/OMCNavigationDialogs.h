#pragma once

#include "CFObj.h"

class OnMyCommandCM;
class CommandRuntimeData;

UInt32 GetNavDialogParams(CFDictionaryRef inFileDialogDict,
                          CFStringRef &outMessage,
                          CFArrayRef &outDefaultName,
                          CFArrayRef &outDefaultLocation);

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
