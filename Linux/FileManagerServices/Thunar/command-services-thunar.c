//
//  command-services-thunar.c
//  Command Workshop file manager services
//
//  The Thunar (Xfce's file manager, thunarx-3: Thunar 4.16 and later) plug-in, the counterpart of
//  the GNOME Files one (../Nautilus/command-services-nautilus.c): a "Services" submenu in the
//  right-click menu, holding the Command applets' file services that fit the selection
//  (../command-services-core.h), or the folder shown when the click is on its background. Choosing
//  one starts the applet with "--command-service <command> <file URIs>"; the applet runs only a
//  command it declares, and a running applet takes the request over from the program started. The
//  lists are read again each time Thunar makes the menu: a few small files, and nothing to watch.
//
//  A selected applet bundle (a <Name>.app folder with a Linux program) also gets "Launch <Name>"
//  in the menu itself, ahead of "Services": it starts the applet as its desktop entry would.
//
//  Installed as root into Thunar's extension folder (/usr/lib/<arch>/thunarx-3), which Thunar
//  loads at its start (thunar -q to restart it).
//

#include <thunarx/thunarx.h>
#include <gmodule.h> // G_MODULE_EXPORT: only Thunar's three entry points are exported (-fvisibility=hidden)
#include "command-services-core.h"

typedef struct _CommandServicesProviderClass
{
	GObjectClass parent_class;
} CommandServicesProviderClass;

typedef struct _CommandServicesProvider
{
	GObject parent_instance;
} CommandServicesProvider;

static void command_services_menu_provider_init(ThunarxMenuProviderIface *inInterface);

THUNARX_DEFINE_TYPE_WITH_CODE(CommandServicesProvider, command_services_provider, G_TYPE_OBJECT,
							  THUNARX_IMPLEMENT_INTERFACE(THUNARX_TYPE_MENU_PROVIDER, command_services_menu_provider_init))

static void
command_services_provider_class_init(CommandServicesProviderClass *inClass)
{
	(void)inClass;
}

static void
command_services_provider_init(CommandServicesProvider *inProvider)
{
	(void)inProvider;
}

// A menu item's label for inText: Thunar makes its menu items with GTK's mnemonic labels, which
// read "_" as the mark of a keyboard shortcut, so each "_" is doubled to be shown
static char *
menu_label(const char *inText)
{
	g_auto(GStrv) parts = g_strsplit(inText, "_", -1);
	return g_strjoinv("__", parts);
}

// A chosen service or launch: its command line, kept on the menu item
static void
on_item_activate(ThunarxMenuItem *inItem, gpointer inData)
{
	(void)inData;
	char **commandLine = g_object_get_data(G_OBJECT(inItem), "command-line");
	if(commandLine == NULL)
		return;
	g_autoptr(GError) error = NULL;
	if(!g_spawn_async(NULL, commandLine, NULL, G_SPAWN_STDOUT_TO_DEV_NULL, NULL, NULL, NULL, &error))
		g_warning("Command services: %s could not be started: %s", commandLine[0], (error != NULL) ? error->message : "unknown error");
}

// The local path of a file Thunar shows, or NULL (a remote file has none). Free with g_free.
static char *
file_info_path(ThunarxFileInfo *inInfo)
{
	g_autoptr(GFile) location = thunarx_file_info_get_location(inInfo);
	return (location != NULL) ? g_file_get_path(location) : NULL;
}

// The "Services" item with a submenu of the services that fit the files, or NULL when none does.
// inFiles: ThunarxFileInfo, each a local file or folder (anything else: no services).
static GList *
services_items(GList *inFiles)
{
	guint fileCount = g_list_length(inFiles);
	if(fileCount == 0)
		return NULL;
	g_autoptr(GPtrArray) types = g_ptr_array_new_with_free_func(g_free);
	g_autoptr(GPtrArray) uris = g_ptr_array_new_with_free_func(g_free);
	for(GList *file = inFiles; file != NULL; file = file->next)
	{
		ThunarxFileInfo *info = THUNARX_FILE_INFO(file->data);
		g_autofree char *path = file_info_path(info);
		if(path == NULL)
			return NULL; // a service runs on local files only
		char *type = thunarx_file_info_is_directory(info) ? g_strdup("inode/directory") : thunarx_file_info_get_mime_type(info);
		if(type == NULL)
			return NULL;
		g_ptr_array_add(types, type);
		// The URI of the path, not of the location: a remote folder mounted through GVfs has a
		// local path but an sftp:// (or other) URI, which the applet refuses as no file
		char *uri = g_filename_to_uri(path, NULL, NULL);
		if(uri == NULL)
			return NULL;
		g_ptr_array_add(uris, uri);
	}

	g_autofree char *folder = command_services_folder();
	g_autoptr(GPtrArray) services = command_services_load(folder);
	ThunarxMenu *submenu = NULL;
	for(guint i = 0; i < services->len; i++)
	{
		const CommandService *service = g_ptr_array_index(services, i);
		if(!command_service_fits(service, (const char *const *)types->pdata, types->len))
			continue;
		if(submenu == NULL)
			submenu = thunarx_menu_new();
		g_autofree char *name = g_strdup_printf("CommandServices::%s::%s", service->application, service->command);
		g_autofree char *label = menu_label(service->title);
		ThunarxMenuItem *item = thunarx_menu_item_new(name, label, service->applet_name, NULL);
		char **commandLine = command_service_command_line(service, (const char *const *)uris->pdata, uris->len);
		g_object_set_data_full(G_OBJECT(item), "command-line", commandLine, (GDestroyNotify)g_strfreev);
		g_signal_connect(item, "activate", G_CALLBACK(on_item_activate), NULL);
		thunarx_menu_append_item(submenu, item);
		g_object_unref(item);
	}
	if(submenu == NULL)
		return NULL;
	ThunarxMenuItem *servicesItem = thunarx_menu_item_new("CommandServices::Services", "Services", NULL, NULL);
	thunarx_menu_item_set_menu(servicesItem, submenu); // takes a reference of its own
	g_object_unref(submenu);
	return g_list_append(NULL, servicesItem);
}

// "Launch <Name>" when the one selected file is an applet bundle with a Linux program
// (command_applet_program), or NULL. It starts the program as the desktop entry does, with no
// arguments; a running applet takes the launch over and comes to the front.
static ThunarxMenuItem *
launch_item(GList *inFiles)
{
	if((inFiles == NULL) || (inFiles->next != NULL))
		return NULL;
	ThunarxFileInfo *info = THUNARX_FILE_INFO(inFiles->data);
	if(!thunarx_file_info_is_directory(info))
		return NULL;
	g_autofree char *path = file_info_path(info);
	g_autofree char *name = NULL;
	char *program = command_applet_program(path, &name);
	if(program == NULL)
		return NULL;
	// A file name need not be UTF-8, and a GTK label must be
	g_autofree char *displayName = g_filename_display_name(name);
	g_autofree char *text = g_strdup_printf("Launch %s", displayName);
	g_autofree char *label = menu_label(text);
	ThunarxMenuItem *item = thunarx_menu_item_new("CommandServices::Launch", label, NULL, NULL);
	char **commandLine = g_new0(char *, 2);
	commandLine[0] = program;
	g_object_set_data_full(G_OBJECT(item), "command-line", commandLine, (GDestroyNotify)g_strfreev);
	g_signal_connect(item, "activate", G_CALLBACK(on_item_activate), NULL);
	return item;
}

// The selection's items: "Launch <Name>" for an applet bundle, then "Services"
static GList *
get_file_menu_items(ThunarxMenuProvider *inProvider, GtkWidget *inWindow, GList *inFiles)
{
	(void)inProvider;
	(void)inWindow;
	GList *items = services_items(inFiles);
	ThunarxMenuItem *launch = launch_item(inFiles);
	if(launch != NULL)
		items = g_list_prepend(items, launch);
	return items;
}

// A click on the folder's background: the folder shown is the one file
static GList *
get_folder_menu_items(ThunarxMenuProvider *inProvider, GtkWidget *inWindow, ThunarxFileInfo *inFolder)
{
	(void)inProvider;
	(void)inWindow;
	if(inFolder == NULL)
		return NULL;
	GList folder = { inFolder, NULL, NULL };
	return services_items(&folder);
}

static void
command_services_menu_provider_init(ThunarxMenuProviderIface *inInterface)
{
	inInterface->get_file_menu_items = get_file_menu_items;
	inInterface->get_folder_menu_items = get_folder_menu_items;
}

static GType sProviderType[1];

G_MODULE_EXPORT void
thunar_extension_initialize(ThunarxProviderPlugin *inPlugin)
{
	const char *mismatch = thunarx_check_version(THUNARX_MAJOR_VERSION, THUNARX_MINOR_VERSION, THUNARX_MICRO_VERSION);
	if(mismatch != NULL)
	{
		g_warning("Command services: this Thunar's extension library does not fit the plug-in: %s", mismatch);
		return;
	}
	command_services_provider_register_type(inPlugin);
	sProviderType[0] = command_services_provider_get_type();
}

G_MODULE_EXPORT void
thunar_extension_shutdown(void)
{
}

G_MODULE_EXPORT void
thunar_extension_list_types(const GType **outTypes, gint *outCount)
{
	*outTypes = sProviderType;
	*outCount = (sProviderType[0] != 0) ? (gint)G_N_ELEMENTS(sProviderType) : 0;
}
