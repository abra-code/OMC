//
//  command-services-core-test.c
//  Command Workshop file manager services
//
//  Tests for command-services-core.c (GLib's test framework), with lists written into a temporary
//  folder. Run: the test program built by build.sh; exit status 0 when all pass.
//

#include "command-services-core.h"
#include <gio/gio.h>
#include <glib/gstdio.h>
#include <string.h>

typedef struct
{
	char *folder;	// the lists
	char *program;	// an executable file the lists name
} Fixture;

static void
write_file(const char *inPath, const char *inText)
{
	g_assert_true(g_file_set_contents(inPath, inText, -1, NULL));
}

static void
fixture_set_up(Fixture *ioFixture, gconstpointer inData)
{
	(void)inData;
	ioFixture->folder = g_dir_make_tmp("command-services-test-XXXXXX", NULL);
	g_assert_nonnull(ioFixture->folder);
	ioFixture->program = g_build_filename(ioFixture->folder, "Applet", NULL);
	write_file(ioFixture->program, "#!/bin/sh\n");
	g_assert_cmpint(g_chmod(ioFixture->program, 0755), ==, 0);
}

static void
fixture_tear_down(Fixture *ioFixture, gconstpointer inData)
{
	(void)inData;
	g_autoptr(GDir) folder = g_dir_open(ioFixture->folder, 0, NULL);
	const char *name = NULL;
	while((folder != NULL) && ((name = g_dir_read_name(folder)) != NULL))
	{
		g_autofree char *path = g_build_filename(ioFixture->folder, name, NULL);
		g_unlink(path);
	}
	g_rmdir(ioFixture->folder);
	g_free(ioFixture->folder);
	g_free(ioFixture->program);
}

// A list for application inID with the given service groups, written as <inFileName>
static void
write_list(Fixture *inFixture, const char *inFileName, const char *inID, const char *inProgram, const char *inServices)
{
	g_autofree char *text = g_strdup_printf("[Applet]\nVersion=1\nApplication=%s\nName=%s Applet\nProgram=%s\n\n%s",
											inID, inID, inProgram, inServices);
	g_autofree char *path = g_build_filename(inFixture->folder, inFileName, NULL);
	write_file(path, text);
}

static void
test_lists_are_read_in_name_order(Fixture *inFixture, gconstpointer inData)
{
	(void)inData;
	write_list(inFixture, "com.example.B.services", "com.example.B", inFixture->program,
			   "[Service 0]\nTitle=Second\nCommand=b.one\nMimeTypes=inode/directory;\n");
	write_list(inFixture, "com.example.A.services", "com.example.A", inFixture->program,
			   "[Service 0]\nTitle=First\nCommand=a.one\nMimeTypes=inode/directory;image/png;\n"
			   "[Service 1]\nTitle=Also first; with a semicolon\nCommand=a.two\nMimeTypes=text/plain;\n");
	g_autoptr(GPtrArray) services = command_services_load(inFixture->folder);
	g_assert_cmpuint(services->len, ==, 3);
	const CommandService *first = g_ptr_array_index(services, 0);
	g_assert_cmpstr(first->application, ==, "com.example.A");
	g_assert_cmpstr(first->applet_name, ==, "com.example.A Applet");
	g_assert_cmpstr(first->program, ==, inFixture->program);
	g_assert_cmpstr(first->title, ==, "First");
	g_assert_cmpstr(first->command, ==, "a.one");
	g_assert_cmpuint(g_strv_length(first->mime_types), ==, 2);
	g_assert_cmpstr(((const CommandService *)g_ptr_array_index(services, 1))->title, ==, "Also first; with a semicolon");
	g_assert_cmpstr(((const CommandService *)g_ptr_array_index(services, 2))->command, ==, "b.one");
}

static void
test_unusable_lists_and_services_are_left_out(Fixture *inFixture, gconstpointer inData)
{
	(void)inData;
	const char *service = "[Service 0]\nTitle=T\nCommand=c\nMimeTypes=inode/directory;\n";
	write_list(inFixture, "no-program.services", "com.example.NoProgram", "/nonexistent/Applet", service);
	write_list(inFixture, "relative.services", "com.example.Relative", "Applet", service);
	write_list(inFixture, "not-executable.services", "com.example.NotExecutable", inFixture->folder, service); // a folder
	g_autofree char *plain = g_build_filename(inFixture->folder, "plain", NULL);
	write_file(plain, "data");
	write_list(inFixture, "plain.services", "com.example.Plain", plain, service);
	g_autofree char *version2 = g_strdup_printf("[Applet]\nVersion=2\nApplication=com.example.V2\nProgram=%s\n\n%s", inFixture->program, service);
	g_autofree char *version2Path = g_build_filename(inFixture->folder, "v2.services", NULL);
	write_file(version2Path, version2);
	g_autofree char *broken = g_build_filename(inFixture->folder, "broken.services", NULL);
	write_file(broken, "not a key file\x01");
	g_autofree char *hidden = g_build_filename(inFixture->folder, ".command-services-123.services", NULL);
	write_file(hidden, version2); // a writer's temporary file
	g_autofree char *other = g_build_filename(inFixture->folder, "other.json", NULL);
	write_file(other, "{}");
	write_list(inFixture, "partial.services", "com.example.Partial", inFixture->program,
			   "[Service 0]\nTitle=\nCommand=c\nMimeTypes=inode/directory;\n"
			   "[Service 1]\nTitle=T\nMimeTypes=inode/directory;\n"
			   "[Service 2]\nTitle=T\nCommand=c\n"
			   "[Service 3]\nTitle=Kept\nCommand=kept\nMimeTypes=inode/directory;\n"
			   "[Other]\nTitle=Not a service\nCommand=x\nMimeTypes=inode/directory;\n");
	g_autoptr(GPtrArray) services = command_services_load(inFixture->folder);
	g_assert_cmpuint(services->len, ==, 1);
	g_assert_cmpstr(((const CommandService *)g_ptr_array_index(services, 0))->command, ==, "kept");
	g_autoptr(GPtrArray) none = command_services_load("/nonexistent/folder");
	g_assert_cmpuint(none->len, ==, 0);
}

static void
test_a_service_fits_when_every_file_does(Fixture *inFixture, gconstpointer inData)
{
	(void)inFixture;
	(void)inData;
	char *types[] = { "inode/directory", "image/png", NULL };
	CommandService service = { "id", "name", "/bin/true", "t", "c", types };
	const char *folder[] = { "inode/directory" };
	const char *png[] = { "image/png" };
	const char *both[] = { "inode/directory", "image/png" };
	const char *mixed[] = { "inode/directory", "text/plain" };
	g_assert_true(command_service_fits(&service, folder, 1));
	g_assert_true(command_service_fits(&service, png, 1));
	g_assert_true(command_service_fits(&service, both, 2));
	g_assert_false(command_service_fits(&service, mixed, 2));
	g_assert_false(command_service_fits(&service, folder, 0));
	const char *missing[] = { NULL };
	g_assert_false(command_service_fits(&service, missing, 1));

	// Any file: a type that is a kind of application/octet-stream fits; a folder is no file
	char *anyFile[] = { "application/octet-stream", NULL };
	CommandService files = { "id", "name", "/bin/true", "t", "c", anyFile };
	g_assert_true(command_service_fits(&files, png, 1));
	g_assert_false(command_service_fits(&files, folder, 1));
	char *text[] = { "text/plain", NULL };
	CommandService texts = { "id", "name", "/bin/true", "t", "c", text };
	const char *shell[] = { "application/x-shellscript" };
	g_assert_true(command_service_fits(&texts, shell, 1)); // a shell script is a kind of text/plain
}

static void
test_the_command_line_asks_the_applet(Fixture *inFixture, gconstpointer inData)
{
	(void)inFixture;
	(void)inData;
	char *types[] = { "inode/directory", NULL };
	CommandService service = { "id", "name", "/apps/Find.app/Contents/Linux/Find", "t", "find.new", types };
	const char *uris[] = { "file:///home/me/a%20b", "file:///home/me/c" };
	g_auto(GStrv) commandLine = command_service_command_line(&service, uris, 2);
	g_assert_cmpuint(g_strv_length(commandLine), ==, 5);
	g_assert_cmpstr(commandLine[0], ==, "/apps/Find.app/Contents/Linux/Find");
	g_assert_cmpstr(commandLine[1], ==, "--command-service");
	g_assert_cmpstr(commandLine[2], ==, "find.new");
	g_assert_cmpstr(commandLine[3], ==, "file:///home/me/a%20b");
	g_assert_cmpstr(commandLine[4], ==, "file:///home/me/c");
}

static void
remove_tree(const char *inPath)
{
	if(g_file_test(inPath, G_FILE_TEST_IS_DIR) && !g_file_test(inPath, G_FILE_TEST_IS_SYMLINK))
	{
		g_autoptr(GDir) folder = g_dir_open(inPath, 0, NULL);
		const char *name = NULL;
		while((folder != NULL) && ((name = g_dir_read_name(folder)) != NULL))
		{
			g_autofree char *path = g_build_filename(inPath, name, NULL);
			remove_tree(path);
		}
		g_rmdir(inPath);
	}
	else
		g_unlink(inPath);
}

// inRoot/<inBundle>/Contents with an Info.plist (unless inInfo is FALSE) and the given files
// (relative to Contents, each made with mode inModes[i])
static char *
make_bundle(const char *inRoot, const char *inBundle, gboolean inInfo, const char *const *inFiles, const int *inModes)
{
	char *bundle = g_build_filename(inRoot, inBundle, NULL);
	g_autofree char *contents = g_build_filename(bundle, "Contents", NULL);
	g_assert_cmpint(g_mkdir_with_parents(contents, 0755), ==, 0);
	if(inInfo)
	{
		g_autofree char *info = g_build_filename(contents, "Info.plist", NULL);
		write_file(info, "<plist/>\n");
	}
	for(gsize i = 0; (inFiles != NULL) && (inFiles[i] != NULL); i++)
	{
		g_autofree char *path = g_build_filename(contents, inFiles[i], NULL);
		g_autofree char *folder = g_path_get_dirname(path);
		g_assert_cmpint(g_mkdir_with_parents(folder, 0755), ==, 0);
		write_file(path, "#!/bin/sh\n");
		g_assert_cmpint(g_chmod(path, inModes[i]), ==, 0);
	}
	return bundle;
}

// Whether command_applet_program finds inExpected (relative to the bundle; NULL: no program), and
// names the applet inName
static void
assert_program(const char *inBundle, const char *inExpected, const char *inName)
{
	g_autofree char *name = NULL;
	g_autofree char *program = command_applet_program(inBundle, &name);
	if(inExpected == NULL)
	{
		g_assert_null(program);
		g_assert_null(name);
		return;
	}
	g_autofree char *expected = g_build_filename(inBundle, inExpected, NULL);
	g_assert_cmpstr(program, ==, expected);
	g_assert_cmpstr(name, ==, inName);
}

static void
test_an_applet_bundle_has_a_program(void)
{
	g_autofree char *root = g_dir_make_tmp("command-applet-test-XXXXXX", NULL);
	g_assert_nonnull(root);
	const char *one[] = { "Linux/Example", NULL };
	const int executable[] = { 0755, 0755 };
	const int plain[] = { 0644 };
	g_autofree char *example = make_bundle(root, "Example.app", TRUE, one, executable);
	assert_program(example, "Contents/Linux/Example", "Example");

	// Renamed after it was made: the one executable in Contents/Linux
	g_autofree char *renamed = make_bundle(root, "Example (copy).app", TRUE, one, executable);
	assert_program(renamed, "Contents/Linux/Example", "Example (copy)");
	const char *two[] = { "Linux/A", "Linux/B", NULL };
	g_autofree char *ambiguous = make_bundle(root, "Renamed.app", TRUE, two, executable);
	assert_program(ambiguous, NULL, NULL);
	const char *named[] = { "Linux/Named", "Linux/Helper", NULL };
	g_autofree char *helper = make_bundle(root, "Named.app", TRUE, named, executable);
	assert_program(helper, "Contents/Linux/Named", "Named"); // its own name first, other files aside

	// Not an applet with a Linux program
	const char *plainOne[] = { "Linux/Plain", NULL };
	g_autofree char *notExecutable = make_bundle(root, "Plain.app", TRUE, plainOne, plain);
	assert_program(notExecutable, NULL, NULL);
	const char *noInfo[] = { "Linux/NoInfo", NULL };
	g_autofree char *noInfoBundle = make_bundle(root, "NoInfo.app", FALSE, noInfo, executable);
	assert_program(noInfoBundle, NULL, NULL);
	const char *mac[] = { "MacOS/Mac", NULL };
	g_autofree char *macOnly = make_bundle(root, "Mac.app", TRUE, mac, executable);
	assert_program(macOnly, NULL, NULL);
	const char *folderOne[] = { "Linux/Folder", NULL };
	g_autofree char *noSuffix = make_bundle(root, "Folder", TRUE, folderOne, executable);
	assert_program(noSuffix, NULL, NULL);
	g_autofree char *bare = make_bundle(root, ".app", TRUE, NULL, NULL);
	assert_program(bare, NULL, NULL);
	g_autofree char *fileApp = g_build_filename(root, "File.app", NULL);
	write_file(fileApp, "not a folder\n");
	assert_program(fileApp, NULL, NULL);
	assert_program("Example.app", NULL, NULL); // a relative path
	g_assert_null(command_applet_program(NULL, NULL));

	remove_tree(root);
}

int
main(int argc, char *argv[])
{
	g_test_init(&argc, &argv, NULL);
	g_test_add("/services/load/order", Fixture, NULL, fixture_set_up, test_lists_are_read_in_name_order, fixture_tear_down);
	g_test_add("/services/load/unusable", Fixture, NULL, fixture_set_up, test_unusable_lists_and_services_are_left_out, fixture_tear_down);
	g_test_add("/services/fits", Fixture, NULL, fixture_set_up, test_a_service_fits_when_every_file_does, fixture_tear_down);
	g_test_add("/services/command-line", Fixture, NULL, fixture_set_up, test_the_command_line_asks_the_applet, fixture_tear_down);
	g_test_add_func("/applet/program", test_an_applet_bundle_has_a_program);
	return g_test_run();
}
