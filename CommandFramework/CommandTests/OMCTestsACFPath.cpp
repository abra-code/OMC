//
//  OMCTestsACFPath.cpp
//  CommandTests
//
//  Compiles Common/ACFPath.cpp into the test bundle on its own (it is not exported from
//  Command.framework). It cannot be included next to OMCStrings.cpp in
//  OMCStringsFoundationParityTests.mm: both files have file-local helpers with the same names.
//

#include "../../Common/ACFPath.cpp"
