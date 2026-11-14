//
//  command-services-core.c
//  Command Workshop file manager services
//
//  See command-services-core.h. The list format is Linux/command-services.py's:
//
//    [Applet]
//    Version=1
//    Application=com.example.Find
//    Name=Find
//    Program=/home/me/Applications/Find.app/Contents/Linux/Find
//
//    [Service 0]
//    Title=Search Here with Find
//    Command=find.new
//    MimeTypes=inode/directory;
//

#include "command-services-core.h"
#include <gio/gio.h>
#include <string.h>

void
command_service_free(CommandService *service)
{
	if(service == NULL)
		return;
	g_free(service->application);
	g_free(service->applet_name);
	g_free(service->program);
	g_free(service->title);
	g_free(service->command);
	g_strfreev(service->mime_types);
	g_free(service);
}

char *
command_services_folder(void)
{
	return g_build_filename(g_get_user_data_dir(), "command", "services", NULL);
}

// The services of one list, appended to ioServices; nothing when the list is not usable
static void
load_list(const char *inPath, GPtrArray *ioServices)
{
	// A regular file only: opening a named pipe would block the file manager until a writer came
	if(!g_file_test(inPath, G_FILE_TEST_IS_REGULAR))
		return;
	g_autoptr(GKeyFile) list = g_key_file_new();
	if(!g_key_file_load_from_file(list, inPath, G_KEY_FILE_NONE, NULL))
		return;
	if(g_key_file_get_integer(list, "Applet", "Version", NULL) != 1)
		return;
	g_autofree char *application = g_key_file_get_string(list, "Applet", "Application", NULL);
	g_autofree char *name = g_key_file_get_locale_string(list, "Applet", "Name", NULL, NULL);
	g_autofree char *program = g_key_file_get_string(list, "Applet", "Program", NULL);
	if((application == NULL) || (program == NULL) || !g_path_is_absolute(program) ||
	   !g_file_test(program, G_FILE_TEST_IS_REGULAR) || !g_file_test(program, G_FILE_TEST_IS_EXECUTABLE))
		return;

	gsize groupCount = 0;
	g_auto(GStrv) groups = g_key_file_get_groups(list, &groupCount);
	for(gsize i = 0; i < groupCount; i++)
	{
		if(!g_str_has_prefix(groups[i], "Service "))
			continue;
		g_autofree char *title = g_key_file_get_locale_string(list, groups[i], "Title", NULL, NULL);
		g_autofree char *command = g_key_file_get_string(list, groups[i], "Command", NULL);
		gsize typeCount = 0;
		g_auto(GStrv) types = g_key_file_get_string_list(list, groups[i], "MimeTypes", &typeCount, NULL);
		if((title == NULL) || (title[0] == '\0') || (command == NULL) || (command[0] == '\0') || (typeCount == 0))
			continue;
		CommandService *service = g_new0(CommandService, 1);
		service->application = g_strdup(application);
		service->applet_name = g_strdup((name != NULL) ? name : application);
		service->program = g_strdup(program);
		service->title = g_steal_pointer(&title);
		service->command = g_steal_pointer(&command);
		service->mime_types = g_steal_pointer(&types);
		g_ptr_array_add(ioServices, service);
	}
}

static gint
compare_names(gconstpointer inA, gconstpointer inB)
{
	return g_strcmp0(*(const char *const *)inA, *(const char *const *)inB);
}

GPtrArray *
command_services_load(const char *inFolder)
{
	GPtrArray *services = g_ptr_array_new_with_free_func((GDestroyNotify)command_service_free);
	if(inFolder == NULL)
		return services;
	g_autoptr(GDir) folder = g_dir_open(inFolder, 0, NULL);
	if(folder == NULL)
		return services;
	g_autoptr(GPtrArray) names = g_ptr_array_new_with_free_func(g_free);
	const char *name = NULL;
	while((name = g_dir_read_name(folder)) != NULL)
	{
		if(g_str_has_suffix(name, ".services") && (name[0] != '.'))
			g_ptr_array_add(names, g_strdup(name));
	}
	g_ptr_array_sort(names, compare_names);
	for(guint i = 0; i < names->len; i++)
	{
		g_autofree char *path = g_build_filename(inFolder, (const char *)g_ptr_array_index(names, i), NULL);
		load_list(path, services);
	}
	return services;
}

gboolean
command_service_fits(const CommandService *inService, const char *const *inFileTypes, gsize inCount)
{
	if((inService == NULL) || (inService->mime_types == NULL) || (inFileTypes == NULL) || (inCount == 0))
		return FALSE;
	for(gsize i = 0; i < inCount; i++)
	{
		if(inFileTypes[i] == NULL)
			return FALSE;
		gboolean fits = FALSE;
		for(char **type = inService->mime_types; !fits && (*type != NULL); type++)
			fits = g_content_type_is_a(inFileTypes[i], *type);
		if(!fits)
			return FALSE;
	}
	return TRUE;
}

char **
command_service_command_line(const CommandService *inService, const char *const *inFileURIs, gsize inCount)
{
	g_autoptr(GStrvBuilder) builder = g_strv_builder_new();
	g_strv_builder_add(builder, inService->program);
	g_strv_builder_add(builder, "--command-service");
	g_strv_builder_add(builder, inService->command);
	for(gsize i = 0; i < inCount; i++)
		g_strv_builder_add(builder, inFileURIs[i]);
	return g_strv_builder_end(builder);
}
