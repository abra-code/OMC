//
//  command-services-core.h
//  Command Workshop file manager services
//
//  What the file manager plug-ins need of the Command applets' services, with GLib only (no file
//  manager): read the services lists Linux/command-services.py writes ($XDG_DATA_HOME/command/services/
//  <application id>.services, key files), choose the services that fit the selected files, and make
//  the command line that asks the applet to run one ("<program> --command-service <command> <URIs>").
//  The applet itself runs only a command it declares as a file service.
//

#pragma once
#include <glib.h>

G_BEGIN_DECLS

typedef struct
{
	char	*application;	// the applet's CFBundleIdentifier
	char	*applet_name;	// its name, for the item's tooltip
	char	*program;		// its program, an absolute path
	char	*title;			// the menu item's title (NSMenuItem)
	char	*command;		// the command id (NSUserData)
	char	**mime_types;	// the types it takes; a file fits one of them, or a type that is one of them
} CommandService;

void		command_service_free(CommandService *service);

// The folder the lists are in: <user data folder>/command/services. Free with g_free.
char		*command_services_folder(void);

// Every service of every list in inFolder, in the lists' name order, then each list's order. A list
// that cannot be read, is not version 1, or whose program is not an executable file is left out;
// so is a service with no title, command or type. Free with g_ptr_array_unref.
GPtrArray	*command_services_load(const char *inFolder);

// Whether every one of the inCount selected files fits the service: each file's type (its MIME
// type, inode/directory for a folder) is one of the service's types or a kind of one of them
// (g_content_type_is_a: an image/png is an application/octet-stream). FALSE for no file.
gboolean	command_service_fits(const CommandService *inService, const char *const *inFileTypes, gsize inCount);

// The command line asking the applet to run the service for the files (file URIs):
// { program, "--command-service", command, uri... , NULL }. Free with g_strfreev.
char		**command_service_command_line(const CommandService *inService, const char *const *inFileURIs, gsize inCount);

// The Linux program of the applet bundle at inPath, a folder <Name>.app in one of the two layouts
// Linux CoreFoundation takes:
// - the Contents layout (Linux/make-applet-bundle.sh's): Contents/Info.plist and the executable
//   Contents/Linux/<Name>;
// - the flat layout: Info.plist and the executable <Name> at the top, and no top-level folder (or
//   symbolic link) named Contents, Resources or Support Files (in any case), with which CF would
//   not read that Info.plist.
// In a bundle renamed after it was made, the one executable file in that folder instead. NULL for
// anything else (a macOS-only app has no Contents/Linux). outName, when not NULL, gets <Name> (the
// folder's name without ".app") for a program found. Free both with g_free.
char		*command_applet_program(const char *inPath, char **outName);

// The icon file of the applet bundle at inPath (one command_applet_program finds a program in), an
// absolute path, as the applet's desktop entry gets it (linux-app-entry.py's icon_path): the file
// CFBundleIconFile names in the layout's resources folder (Contents/Resources, or the top folder of
// the flat layout) when it is an SVG or a PNG, else that name with .svg, then .png. NULL when the
// bundle has no program, its Info.plist is not an XML property list with that key, or there is no
// such file (a macOS bundle names only its .icns). Free with g_free.
char		*command_applet_icon(const char *inPath);

G_END_DECLS
