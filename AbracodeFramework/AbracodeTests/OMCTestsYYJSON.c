//
//  OMCTestsYYJSON.c
//  AbracodeTests
//
//  Compiles the vendored yyjson into the test bundle for OMCJSONFoundationParityTests, which
//  includes Common/ACFJSON.cpp directly (neither is exported from Abracode.framework). yyjson is
//  third-party code kept unmodified (ThirdParty/yyjson/README.md), so its warnings under this
//  project's settings are not ours to fix.
//

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Weverything"
#include "../../ThirdParty/yyjson/yyjson.c"
#pragma clang diagnostic pop
