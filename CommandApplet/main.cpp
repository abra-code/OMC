//
//  main.cpp (Linux)
//  CommandApplet
//
//  The Linux applet executable: the engine's app shell runs the applet in the bundle this
//  executable is in (AbracodeFramework/EntryPoints/Linux/OMCAppletMain.cpp). Every Linux applet's
//  executable is this one, renamed: Linux/make-applet-bundle.sh puts it in a bundle, and
//  build-linux.sh makes CommandApplet.app, the master applet, from this folder.
//

#include "OMCAppletMain.h"

int
main(int argc, char *argv[])
{
	return OMCAppletMain(argc, argv);
}
