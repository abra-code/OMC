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
#include <glib/gstdio.h>
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

static gboolean
is_executable_file(const char *inPath)
{
	return g_file_test(inPath, G_FILE_TEST_IS_REGULAR) && g_file_test(inPath, G_FILE_TEST_IS_EXECUTABLE);
}

// The one executable file in inFolder, or NULL when there is none or more than one
static char *
only_executable_in(const char *inFolder)
{
	g_autoptr(GDir) folder = g_dir_open(inFolder, 0, NULL);
	if(folder == NULL)
		return NULL;
	char *found = NULL;
	const char *name = NULL;
	while((name = g_dir_read_name(folder)) != NULL)
	{
		g_autofree char *path = g_build_filename(inFolder, name, NULL);
		if(!is_executable_file(path))
			continue;
		if(found != NULL)
		{
			g_free(found);
			return NULL;
		}
		found = g_steal_pointer(&path);
	}
	return found;
}

// Whether inFolder holds a folder or symbolic link (to anything) named Contents, Resources or
// Support Files, in any case: Linux CoreFoundation then takes the bundle for an old-style one and
// does not read a top-level Info.plist (~/git/AppleCoreLibrariesForLinux/build/probe/cfbundle-layout,
// layout B; CF's _CFBundleGetBundleVersionForURL counts DT_DIR and DT_LNK entries by these names)
static gboolean
has_layout_folder(const char *inFolder)
{
	g_autoptr(GDir) folder = g_dir_open(inFolder, 0, NULL);
	const char *name = NULL;
	while((folder != NULL) && ((name = g_dir_read_name(folder)) != NULL))
	{
		if((g_ascii_strcasecmp(name, "Contents") != 0) && (g_ascii_strcasecmp(name, "Resources") != 0)
			&& (g_ascii_strcasecmp(name, "Support Files") != 0))
			continue;
		g_autofree char *path = g_build_filename(inFolder, name, NULL);
		if(g_file_test(path, G_FILE_TEST_IS_DIR | G_FILE_TEST_IS_SYMLINK))
			return TRUE;
	}
	return FALSE;
}

// The program in inFolder: <inName>, else the one executable file there (a renamed bundle)
static char *
program_in(const char *inFolder, const char *inName)
{
	char *program = g_build_filename(inFolder, inName, NULL);
	if(is_executable_file(program))
		return program;
	g_free(program);
	return only_executable_in(inFolder);
}

char *
command_applet_program(const char *inPath, char **outName)
{
	if(outName != NULL)
		*outName = NULL;
	if((inPath == NULL) || !g_path_is_absolute(inPath))
		return NULL;
	g_autofree char *base = g_path_get_basename(inPath);
	gsize baseLength = strlen(base);
	if((baseLength <= 4) || !g_str_has_suffix(base, ".app") || !g_file_test(inPath, G_FILE_TEST_IS_DIR))
		return NULL;
	g_autofree char *name = g_strndup(base, baseLength - 4);
	char *program = NULL;
	g_autofree char *contentsInfo = g_build_filename(inPath, "Contents", "Info.plist", NULL);
	g_autofree char *flatInfo = g_build_filename(inPath, "Info.plist", NULL);
	if(g_file_test(contentsInfo, G_FILE_TEST_IS_REGULAR))
	{
		g_autofree char *linuxFolder = g_build_filename(inPath, "Contents", "Linux", NULL);
		program = program_in(linuxFolder, name);
	}
	else if(g_file_test(flatInfo, G_FILE_TEST_IS_REGULAR) && !has_layout_folder(inPath))
		program = program_in(inPath, name);
	if((program != NULL) && (outName != NULL))
		*outName = g_steal_pointer(&name);
	return program;
}

// What read_icon_key's parser tracks: the depth of the element it is in (1: plist, 2: the top
// dictionary, 3: an item of it), the text of the element at depth 3, and whether the last key read
// at depth 3 was CFBundleIconFile, so that the element after it is the value
typedef struct
{
	int		depth;
	GString	*text;
	gboolean	keyMatched;
	gboolean	inTopDict;
	char	*value;
} IconKeyParse;

static void
icon_key_start(GMarkupParseContext *inContext, const char *inElement, const char **inNames,
			   const char **inValues, gpointer inData, GError **outError)
{
	IconKeyParse *parse = inData;
	parse->depth++;
	if(parse->depth == 2)
		parse->inTopDict = (strcmp(inElement, "dict") == 0);
	if(parse->depth == 3)
		g_string_truncate(parse->text, 0);
}

static void
icon_key_end(GMarkupParseContext *inContext, const char *inElement, gpointer inData, GError **outError)
{
	IconKeyParse *parse = inData;
	if((parse->depth == 3) && parse->inTopDict)
	{
		if(strcmp(inElement, "key") == 0)
			parse->keyMatched = (strcmp(parse->text->str, "CFBundleIconFile") == 0);
		else
		{
			// The value that follows the key: a string, or nothing usable
			if(parse->keyMatched && (parse->value == NULL) && (strcmp(inElement, "string") == 0))
				parse->value = g_strdup(parse->text->str);
			parse->keyMatched = FALSE;
		}
	}
	parse->depth--;
}

static void
icon_key_text(GMarkupParseContext *inContext, const char *inText, gsize inLength, gpointer inData, GError **outError)
{
	IconKeyParse *parse = inData;
	if(parse->depth == 3)
		g_string_append_len(parse->text, inText, (gssize)inLength);
}

// CFBundleIconFile of the XML property list at inPath (a top-level key of its top dictionary), or
// NULL: no such key, not a string, or a file that is not an XML property list (a binary one too,
// which Linux bundles are not written as; the caller then shows no icon of the applet's own)
static char *
read_icon_key(const char *inPath)
{
	// A regular file (opening a named pipe would block the file manager until a writer came) of at
	// most 1 MiB, checked before the read: g_file_get_contents reads the whole file, so a huge (or
	// sparse) Info.plist would otherwise be read into memory first. The length is checked again
	// after it, for a file that grew meanwhile.
	GStatBuf status;
	if((g_stat(inPath, &status) != 0) || !S_ISREG(status.st_mode) || (status.st_size > 1024 * 1024))
		return NULL;
	g_autofree char *contents = NULL;
	gsize length = 0;
	if(!g_file_get_contents(inPath, &contents, &length, NULL) || (length > 1024 * 1024) || g_str_has_prefix(contents, "bplist"))
		return NULL;
	GMarkupParser parser = { icon_key_start, icon_key_end, icon_key_text, NULL, NULL };
	IconKeyParse parse = { 0, g_string_new(NULL), FALSE, FALSE, NULL };
	GMarkupParseContext *context = g_markup_parse_context_new(&parser, G_MARKUP_TREAT_CDATA_AS_TEXT, &parse, NULL);
	gboolean parsed = g_markup_parse_context_parse(context, contents, (gssize)length, NULL) &&
					  g_markup_parse_context_end_parse(context, NULL);
	g_markup_parse_context_free(context);
	g_string_free(parse.text, TRUE);
	if(!parsed)
	{
		g_free(parse.value);
		return NULL;
	}
	return parse.value;
}

// inFolder/inName when it is a regular file, else NULL
static char *
regular_file_in(const char *inFolder, const char *inName)
{
	char *path = g_build_filename(inFolder, inName, NULL);
	if(g_file_test(path, G_FILE_TEST_IS_REGULAR))
		return path;
	g_free(path);
	return NULL;
}

char *
command_applet_icon(const char *inPath)
{
	g_autofree char *program = command_applet_program(inPath, NULL);
	if(program == NULL)
		return NULL;
	// The layout command_applet_program took the program from: the Contents layout when it has
	// its Info.plist, else the flat one
	g_autofree char *contentsInfo = g_build_filename(inPath, "Contents", "Info.plist", NULL);
	gboolean contentsLayout = g_file_test(contentsInfo, G_FILE_TEST_IS_REGULAR);
	g_autofree char *infoPath = contentsLayout ? g_strdup(contentsInfo) : g_build_filename(inPath, "Info.plist", NULL);
	g_autofree char *resources = contentsLayout ? g_build_filename(inPath, "Contents", "Resources", NULL) : g_strdup(inPath);
	g_autofree char *iconFile = read_icon_key(infoPath);
	if((iconFile == NULL) || (iconFile[0] == '\0') || (strchr(iconFile, '/') != NULL))
		return NULL;

	// linux-app-entry.py's icon_path: the file itself when it is an SVG or a PNG, else its name
	// with .svg, then .png. The extension is what follows the last dot, leading dots aside (Python's
	// os.path.splitext), so ".png" has none.
	const char *afterDots = iconFile + strspn(iconFile, ".");
	const char *dot = strrchr(afterDots, '.');
	g_autofree char *base = (dot != NULL) ? g_strndup(iconFile, (gsize)(dot - iconFile)) : g_strdup(iconFile);
	if((dot != NULL) && ((g_ascii_strcasecmp(dot, ".svg") == 0) || (g_ascii_strcasecmp(dot, ".png") == 0)))
	{
		char *named = regular_file_in(resources, iconFile);
		if(named != NULL)
			return named;
	}
	g_autofree char *svgName = g_strconcat(base, ".svg", NULL);
	char *found = regular_file_in(resources, svgName);
	if(found != NULL)
		return found;
	g_autofree char *pngName = g_strconcat(base, ".png", NULL);
	return regular_file_in(resources, pngName);
}
