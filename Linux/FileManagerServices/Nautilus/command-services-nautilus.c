//
//  command-services-nautilus.c
//  Command Workshop file manager services
//
//  The GNOME Files (Nautilus 43 and later) plug-in: a "Services" submenu in the right-click menu,
//  holding the Command applets' file services that fit the selection (command-services-core.h), or the
//  folder shown when the click is on its background. Choosing one starts the applet with
//  "--command-service <command> <file URIs>"; the applet runs only a command it declares, and a running
//  applet takes the request over from the program started. The lists are read again each time
//  Nautilus makes the menu (it remakes extension menus, throttled, as the selection or the folder's
//  files change): a few small files, and nothing to watch.
//
//  A selected applet bundle (a <Name>.app folder with a Linux program) also gets "Launch <Name>"
//  in the menu itself, ahead of "Services": it starts the applet as its desktop entry would. It has
//  no icon: GNOME Files shows none on extension items (Dolphin's and Thunar's show the applet's).
//
//  Installed as root into Nautilus's extension folder (/usr/lib/<arch>/nautilus/extensions-4),
//  which Nautilus loads at its start (nautilus -q to restart it).
//

#include <nautilus-extension.h>
#include <gmodule.h> // G_MODULE_EXPORT: only Nautilus's three entry points are exported (-fvisibility=hidden)
#include "command-services-core.h"

#define COMMAND_TYPE_SERVICES_PROVIDER (command_services_provider_get_type())
G_DECLARE_FINAL_TYPE(CommandServicesProvider, command_services_provider, COMMAND, SERVICES_PROVIDER, GObject)

struct _CommandServicesProvider
{
	GObject parent_instance;
};

static void command_services_menu_provider_init(NautilusMenuProviderInterface *inInterface);

G_DEFINE_DYNAMIC_TYPE_EXTENDED(CommandServicesProvider, command_services_provider, G_TYPE_OBJECT, 0,
							   G_IMPLEMENT_INTERFACE_DYNAMIC(NAUTILUS_TYPE_MENU_PROVIDER, command_services_menu_provider_init))

static void
command_services_provider_class_init(CommandServicesProviderClass *inClass)
{
	(void)inClass;
}

static void
command_services_provider_class_finalize(CommandServicesProviderClass *inClass)
{
	(void)inClass;
}

static void
command_services_provider_init(CommandServicesProvider *inProvider)
{
	(void)inProvider;
}

// A menu item's label for inText: Nautilus gives an extension's labels to GTK as they are, and GTK
// reads "_" as the mark of a keyboard shortcut (Nautilus 48.3's nautilus-files-view.c doubles them
// in its own file names, escape_underscores), so each "_" is doubled to be shown
static char *
menu_label(const char *inText)
{
	g_auto(GStrv) parts = g_strsplit(inText, "_", -1);
	return g_strjoinv("__", parts);
}

// A chosen service or launch: its command line, kept on the menu item
static void
on_item_activate(NautilusMenuItem *inItem, gpointer inData)
{
	(void)inData;
	char **commandLine = g_object_get_data(G_OBJECT(inItem), "command-line");
	if(commandLine == NULL)
		return;
	g_autoptr(GError) error = NULL;
	if(!g_spawn_async(NULL, commandLine, NULL, G_SPAWN_STDOUT_TO_DEV_NULL, NULL, NULL, NULL, &error))
		g_warning("Command services: %s could not be started: %s", commandLine[0], (error != NULL) ? error->message : "unknown error");
}

// The "Services" item with a submenu of the services that fit the files, or NULL when none does.
// inFiles: NautilusFileInfo, each a local file or folder (anything else: no services).
// inNamePrefix: the start of each item's name, different for the selection's menu and the
// background's: Nautilus names an item's action after its menu's prefix, its position and its name,
// with one prefix for both menus, and adds both menus' actions to one group, so a background item
// named as the selection's took its action over (Nautilus 48.3: a service chosen for a selected
// folder ran for the folder shown).
static GList *
services_items(GList *inFiles, const char *inNamePrefix)
{
	guint fileCount = g_list_length(inFiles);
	if(fileCount == 0)
		return NULL;
	g_autoptr(GPtrArray) types = g_ptr_array_new_with_free_func(g_free);
	g_autoptr(GPtrArray) uris = g_ptr_array_new_with_free_func(g_free);
	for(GList *file = inFiles; file != NULL; file = file->next)
	{
		NautilusFileInfo *info = NAUTILUS_FILE_INFO(file->data);
		g_autoptr(GFile) location = nautilus_file_info_get_location(info);
		g_autofree char *path = (location != NULL) ? g_file_get_path(location) : NULL;
		if((path == NULL) || nautilus_file_info_is_gone(info))
			return NULL; // a service runs on local files only
		char *type = nautilus_file_info_is_directory(info) ? g_strdup("inode/directory") : nautilus_file_info_get_mime_type(info);
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
	NautilusMenu *submenu = NULL;
	for(guint i = 0; i < services->len; i++)
	{
		const CommandService *service = g_ptr_array_index(services, i);
		if(!command_service_fits(service, (const char *const *)types->pdata, types->len))
			continue;
		if(submenu == NULL)
			submenu = nautilus_menu_new();
		g_autofree char *name = g_strdup_printf("%s::%s::%s", inNamePrefix, service->application, service->command);
		g_autofree char *label = menu_label(service->title);
		NautilusMenuItem *item = nautilus_menu_item_new(name, label, service->applet_name, NULL);
		char **commandLine = command_service_command_line(service, (const char *const *)uris->pdata, uris->len);
		g_object_set_data_full(G_OBJECT(item), "command-line", commandLine, (GDestroyNotify)g_strfreev);
		g_signal_connect(item, "activate", G_CALLBACK(on_item_activate), NULL);
		nautilus_menu_append_item(submenu, item);
		g_object_unref(item);
	}
	if(submenu == NULL)
		return NULL;
	g_autofree char *servicesName = g_strdup_printf("%s::Services", inNamePrefix);
	NautilusMenuItem *servicesItem = nautilus_menu_item_new(servicesName, "Services", NULL, NULL);
	nautilus_menu_item_set_submenu(servicesItem, submenu); // takes a reference of its own
	g_object_unref(submenu);
	return g_list_append(NULL, servicesItem);
}

// "Launch <Name>" when the one selected file is an applet bundle with a Linux program
// (command_applet_program), or NULL. It starts the program as the desktop entry does, with no
// arguments; a running applet takes the launch over and comes to the front.
static NautilusMenuItem *
launch_item(GList *inFiles)
{
	if((inFiles == NULL) || (inFiles->next != NULL))
		return NULL;
	NautilusFileInfo *info = NAUTILUS_FILE_INFO(inFiles->data);
	if(nautilus_file_info_is_gone(info) || !nautilus_file_info_is_directory(info))
		return NULL;
	g_autoptr(GFile) location = nautilus_file_info_get_location(info);
	g_autofree char *path = (location != NULL) ? g_file_get_path(location) : NULL;
	g_autofree char *name = NULL;
	char *program = command_applet_program(path, &name);
	if(program == NULL)
		return NULL;
	// A file name need not be UTF-8, and Nautilus puts the label in a GMenu (a UTF-8 GVariant)
	g_autofree char *displayName = g_filename_display_name(name);
	g_autofree char *text = g_strdup_printf("Launch %s", displayName);
	g_autofree char *label = menu_label(text);
	NautilusMenuItem *item = nautilus_menu_item_new("CommandServices::Launch", label, NULL, NULL);
	char **commandLine = g_new0(char *, 2);
	commandLine[0] = program;
	g_object_set_data_full(G_OBJECT(item), "command-line", commandLine, (GDestroyNotify)g_strfreev);
	g_signal_connect(item, "activate", G_CALLBACK(on_item_activate), NULL);
	return item;
}

// The selection's items: "Launch <Name>" for an applet bundle, then "Services"
static GList *
get_file_items(NautilusMenuProvider *inProvider, GList *inFiles)
{
	(void)inProvider;
	GList *items = services_items(inFiles, "CommandServices");
	NautilusMenuItem *launch = launch_item(inFiles);
	if(launch != NULL)
		items = g_list_prepend(items, launch);
	return items;
}

// A click on the folder's background: the folder shown is the one file
static GList *
get_background_items(NautilusMenuProvider *inProvider, NautilusFileInfo *inCurrentFolder)
{
	(void)inProvider;
	if(inCurrentFolder == NULL)
		return NULL;
	GList folder = { inCurrentFolder, NULL, NULL };
	return services_items(&folder, "CommandServices::Background");
}

static void
command_services_menu_provider_init(NautilusMenuProviderInterface *inInterface)
{
	inInterface->get_file_items = get_file_items;
	inInterface->get_background_items = get_background_items;
}

static GType sProviderType[1];

G_MODULE_EXPORT void
nautilus_module_initialize(GTypeModule *inModule)
{
	command_services_provider_register_type(inModule);
	sProviderType[0] = COMMAND_TYPE_SERVICES_PROVIDER;
}

G_MODULE_EXPORT void
nautilus_module_shutdown(void)
{
}

G_MODULE_EXPORT void
nautilus_module_list_types(const GType **outTypes, int *outCount)
{
	*outTypes = sProviderType;
	*outCount = G_N_ELEMENTS(sProviderType);
}
