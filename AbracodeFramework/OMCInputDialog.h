//
//  OMCInputDialog.h
//  Abracode
//
//  Created by Tomasz Kukielka on 8/25/09.
//  Copyright 2009-2010 Abracode. All rights reserved.
//

class OnMyCommandCM;
class CommandRuntimeData;

//returns true if OKeyed and outStringRef is retained so caller responsible for releasing it
Boolean RunCocoaInputDialog(OnMyCommandCM *inPlugin,
                            CommandRuntimeData &commandRuntimeData);
