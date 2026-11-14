//
//  command-services-nautilus-test.c
//  Command Workshop file manager services
//
//  The GNOME Files plug-in (libcommand-services-nautilus.so) loaded as Nautilus loads it
//  (nautilus_module_initialize, nautilus_module_list_types) and asked for its menu with stand-in
//  files, so its menu building and its activation are tested without Nautilus or root. The
//  services list is written into a temporary data folder (XDG_DATA_HOME), its program a script
//  that writes its arguments to a file.
//
//  Usage: command-services-nautilus-test <path of libcommand-services-nautilus.so>
//

#include <nautilus-extension.h>
#include <gmodule.h>
#include <glib/gstdio.h>
#include <string.h>

// -- a stand-in file

#define TEST_TYPE_FILE (test_file_get_type())
G_DECLARE_FINAL_TYPE(TestFile, test_file, TEST, FILE, GObject)

struct _TestFile
{
	GObject parent_instance;
	char *path;
	char *mime_type;
	gboolean is_directory;
};

static void test_file_info_init(NautilusFileInfoInterface *inInterface);

G_DEFINE_TYPE_WITH_CODE(TestFile, test_file, G_TYPE_OBJECT,
						G_IMPLEMENT_INTERFACE(NAUTILUS_TYPE_FILE_INFO, test_file_info_init))

static void
test_file_finalize(GObject *inObject)
{
	TestFile *file = TEST_FILE(inObject);
	g_free(file->path);
	g_free(file->mime_type);
	G_OBJECT_CLASS(test_file_parent_class)->finalize(inObject);
}

static void test_file_class_init(TestFileClass *inClass) { G_OBJECT_CLASS(inClass)->finalize = test_file_finalize; }
static void test_file_init(TestFile *inFile) { (void)inFile; }

static gboolean file_is_gone(NautilusFileInfo *inInfo) { (void)inInfo; return FALSE; }
static char *file_get_mime_type(NautilusFileInfo *inInfo) { return g_strdup(TEST_FILE(inInfo)->mime_type); }
static gboolean file_is_directory(NautilusFileInfo *inInfo) { return TEST_FILE(inInfo)->is_directory; }
static GFile *file_get_location(NautilusFileInfo *inInfo) { return g_file_new_for_path(TEST_FILE(inInfo)->path); }
static char *file_get_uri(NautilusFileInfo *inInfo) { return g_filename_to_uri(TEST_FILE(inInfo)->path, NULL, NULL); }

static void
test_file_info_init(NautilusFileInfoInterface *inInterface)
{
	inInterface->is_gone = file_is_gone;
	inInterface->get_mime_type = file_get_mime_type;
	inInterface->is_directory = file_is_directory;
	inInterface->get_location = file_get_location;
	inInterface->get_uri = file_get_uri;
}

static NautilusFileInfo *
make_file(const char *inPath, const char *inMimeType, gboolean inIsDirectory)
{
	TestFile *file = g_object_new(TEST_TYPE_FILE, NULL);
	file->path = g_strdup(inPath);
	file->mime_type = g_strdup(inMimeType);
	file->is_directory = inIsDirectory;
	return NAUTILUS_FILE_INFO(file);
}

// -- a type module, as Nautilus gives each plug-in

#define TEST_TYPE_MODULE (test_module_get_type())
G_DECLARE_FINAL_TYPE(TestModule, test_module, TEST, MODULE, GTypeModule)
struct _TestModule { GTypeModule parent_instance; };
G_DEFINE_TYPE(TestModule, test_module, G_TYPE_TYPE_MODULE)
static gboolean module_load(GTypeModule *inModule) { (void)inModule; return TRUE; }
static void module_unload(GTypeModule *inModule) { (void)inModule; }
static void test_module_class_init(TestModuleClass *inClass)
{
	G_TYPE_MODULE_CLASS(inClass)->load = module_load;
	G_TYPE_MODULE_CLASS(inClass)->unload = module_unload;
}
static void test_module_init(TestModule *inModule) { (void)inModule; }

// -- the tests

static const char *sPluginPath = NULL;
static char *sData = NULL;			// XDG_DATA_HOME
static char *sWork = NULL;			// the files, the program and its output
static char *sOutput = NULL;		// what the program was started with
static NautilusMenuProvider *sProvider = NULL;

static void
write_file(const char *inPath, const char *inText)
{
	g_assert_true(g_file_set_contents(inPath, inText, -1, NULL));
}

// The labels of the "Services" item's submenu, joined with "|"; "" for no item
static char *
services_labels(GList *inItems)
{
	if(inItems == NULL)
		return g_strdup("");
	g_assert_cmpuint(g_list_length(inItems), ==, 1);
	g_autofree char *label = NULL;
	NautilusMenu *menu = NULL;
	g_object_get(inItems->data, "label", &label, "menu", &menu, NULL);
	g_assert_cmpstr(label, ==, "Services");
	g_assert_nonnull(menu);
	GList *items = nautilus_menu_get_items(menu);
	g_autoptr(GString) labels = g_string_new(NULL);
	for(GList *item = items; item != NULL; item = item->next)
	{
		g_autofree char *itemLabel = NULL;
		g_object_get(item->data, "label", &itemLabel, NULL);
		g_string_append_printf(labels, "%s%s", (labels->len > 0) ? "|" : "", itemLabel);
	}
	nautilus_menu_item_list_free(items);
	g_object_unref(menu);
	return g_string_free(g_steal_pointer(&labels), FALSE);
}

static void
test_items_for_the_selection(void)
{
	g_autofree char *folderPath = g_build_filename(sWork, "a folder", NULL);
	g_autofree char *textPath = g_build_filename(sWork, "notes.txt", NULL);
	g_autofree char *pngPath = g_build_filename(sWork, "picture.png", NULL);
	g_autoptr(NautilusFileInfo) folder = make_file(folderPath, "inode/directory", TRUE);
	g_autoptr(NautilusFileInfo) text = make_file(textPath, "text/plain", FALSE);
	g_autoptr(NautilusFileInfo) png = make_file(pngPath, "image/png", FALSE);

	GList *oneFolder = g_list_append(NULL, folder);
	GList *items = nautilus_menu_provider_get_file_items(sProvider, oneFolder);
	g_autofree char *labels = services_labels(items);
	g_assert_cmpstr(labels, ==, "Any File Or Folder|Search Here"); // the lists in name order: Any, then Find
	nautilus_menu_item_list_free(items);
	g_list_free(oneFolder);

	GList *oneText = g_list_append(NULL, text);
	items = nautilus_menu_provider_get_file_items(sProvider, oneText);
	g_autofree char *textLabels = services_labels(items);
	g_assert_cmpstr(textLabels, ==, "Any File Or Folder|Text Tool");
	nautilus_menu_item_list_free(items);
	g_list_free(oneText);

	GList *textAndPng = g_list_append(g_list_append(NULL, text), png);
	items = nautilus_menu_provider_get_file_items(sProvider, textAndPng);
	g_autofree char *mixedLabels = services_labels(items);
	g_assert_cmpstr(mixedLabels, ==, "Any File Or Folder"); // the text tool takes text only
	nautilus_menu_item_list_free(items);
	g_list_free(textAndPng);

	// The folder's background: the folder shown is the one file
	items = nautilus_menu_provider_get_background_items(sProvider, folder);
	g_autofree char *backgroundLabels = services_labels(items);
	g_assert_cmpstr(backgroundLabels, ==, "Any File Or Folder|Search Here");
	nautilus_menu_item_list_free(items);

	// Nothing fits: no Services item at all
	g_autofree char *listPath = g_build_filename(sData, "command", "services", "com.example.Any.services", NULL);
	g_autofree char *kept = NULL;
	g_assert_true(g_file_get_contents(listPath, &kept, NULL, NULL));
	g_unlink(listPath);
	GList *onePng = g_list_append(NULL, png);
	items = nautilus_menu_provider_get_file_items(sProvider, onePng);
	g_assert_null(items);
	g_list_free(onePng);
	write_file(listPath, kept);
}

static void
test_choosing_a_service_starts_the_applet(void)
{
	g_autofree char *folderPath = g_build_filename(sWork, "a folder", NULL);
	g_autoptr(NautilusFileInfo) folder = make_file(folderPath, "inode/directory", TRUE);
	GList *oneFolder = g_list_append(NULL, folder);
	GList *items = nautilus_menu_provider_get_file_items(sProvider, oneFolder);
	g_list_free(oneFolder);
	g_assert_nonnull(items);
	NautilusMenu *menu = NULL;
	g_object_get(items->data, "menu", &menu, NULL);
	GList *serviceItems = nautilus_menu_get_items(menu);
	NautilusMenuItem *searchHere = NULL;
	for(GList *item = serviceItems; (item != NULL) && (searchHere == NULL); item = item->next)
	{
		g_autofree char *label = NULL;
		g_object_get(item->data, "label", &label, NULL);
		if(g_strcmp0(label, "Search Here") == 0)
			searchHere = NAUTILUS_MENU_ITEM(item->data);
	}
	g_assert_nonnull(searchHere);
	g_unlink(sOutput);
	nautilus_menu_item_activate(searchHere);
	g_autofree char *started = NULL;
	for(int tenths = 0; (tenths < 50) && !g_file_get_contents(sOutput, &started, NULL, NULL); tenths++)
		g_usleep(100000);
	g_assert_nonnull(started);
	g_autofree char *uri = g_filename_to_uri(folderPath, NULL, NULL);
	g_autofree char *expected = g_strdup_printf("--command-service\nfind.new\n%s\n", uri);
	g_assert_cmpstr(started, ==, expected);
	nautilus_menu_item_list_free(serviceItems);
	g_object_unref(menu);
	nautilus_menu_item_list_free(items);
}

static void
write_lists(void)
{
	g_autofree char *folder = g_build_filename(sData, "command", "services", NULL);
	g_assert_cmpint(g_mkdir_with_parents(folder, 0700), ==, 0);
	g_autofree char *program = g_build_filename(sWork, "Applet", NULL);
	sOutput = g_build_filename(sWork, "started", NULL);
	g_autofree char *script = g_strdup_printf("#!/bin/sh\nprintf '%%s\\n' \"$@\" > '%s.part' && mv '%s.part' '%s'\n", sOutput, sOutput, sOutput);
	write_file(program, script);
	g_assert_cmpint(g_chmod(program, 0755), ==, 0);
	g_autofree char *find = g_strdup_printf("[Applet]\nVersion=1\nApplication=com.example.Find\nName=Find\nProgram=%s\n\n"
											"[Service 0]\nTitle=Search Here\nCommand=find.new\nMimeTypes=inode/directory;\n", program);
	g_autofree char *any = g_strdup_printf("[Applet]\nVersion=1\nApplication=com.example.Any\nName=Any\nProgram=%s\n\n"
										   "[Service 0]\nTitle=Any File Or Folder\nCommand=any.run\nMimeTypes=application/octet-stream;inode/directory;\n"
										   "[Service 1]\nTitle=Text Tool\nCommand=text.run\nMimeTypes=text/plain;\n", program);
	g_autofree char *findPath = g_build_filename(folder, "com.example.Find.services", NULL);
	g_autofree char *anyPath = g_build_filename(folder, "com.example.Any.services", NULL);
	write_file(findPath, find);
	write_file(anyPath, any);
}

int
main(int argc, char *argv[])
{
	g_test_init(&argc, &argv, NULL);
	if(argc < 2)
	{
		g_printerr("usage: %s <libcommand-services-nautilus.so>\n", argv[0]);
		return 2;
	}
	sPluginPath = argv[1];
	sWork = g_dir_make_tmp("command-services-plugin-test-XXXXXX", NULL);
	sData = g_build_filename(sWork, "data", NULL);
	g_setenv("XDG_DATA_HOME", sData, TRUE); // before GLib reads it
	write_lists();

	GModule *plugin = g_module_open(sPluginPath, G_MODULE_BIND_LOCAL);
	if(plugin == NULL)
	{
		g_printerr("cannot load %s: %s\n", sPluginPath, g_module_error());
		return 1;
	}
	void (*initialize)(GTypeModule *) = NULL;
	void (*listTypes)(const GType **, int *) = NULL;
	g_assert_true(g_module_symbol(plugin, "nautilus_module_initialize", (gpointer *)&initialize));
	g_assert_true(g_module_symbol(plugin, "nautilus_module_list_types", (gpointer *)&listTypes));
	GTypeModule *module = g_object_new(TEST_TYPE_MODULE, NULL);
	g_assert_true(g_type_module_use(module));
	initialize(module);
	const GType *types = NULL;
	int typeCount = 0;
	listTypes(&types, &typeCount);
	g_assert_cmpint(typeCount, ==, 1);
	g_assert_true(g_type_is_a(types[0], NAUTILUS_TYPE_MENU_PROVIDER));
	sProvider = NAUTILUS_MENU_PROVIDER(g_object_new(types[0], NULL));

	g_test_add_func("/plugin/items", test_items_for_the_selection);
	g_test_add_func("/plugin/activate", test_choosing_a_service_starts_the_applet);
	return g_test_run();
}
