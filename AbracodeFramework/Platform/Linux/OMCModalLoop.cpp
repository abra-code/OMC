//
//  OMCModalLoop.cpp
//  Abracode
//
//  See OMCModalLoop.h. Linux only.
//

#include "OMCModalLoop.h"
#include <algorithm>
#include <vector>

namespace
{

// The loops OMCRunModalLoop is running, innermost last
std::vector<GMainLoop *> sRunningLoops;

} // namespace

void
OMCRunModalLoop(GMainLoop *inLoop)
{
	if(inLoop == nullptr)
		return;
	sRunningLoops.push_back(inLoop);
	g_main_loop_run(inLoop);
	sRunningLoops.erase(std::remove(sRunningLoops.begin(), sRunningLoops.end(), inLoop), sRunningLoops.end());
}

void
OMCEndModalLoops()
{
	for(GMainLoop *loop : sRunningLoops)
	{
		if(g_main_loop_is_running(loop))
			g_main_loop_quit(loop);
	}
}
