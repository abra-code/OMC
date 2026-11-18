//
//  command-services-dolphin-test.cpp
//  Command Workshop file manager services
//
//  The Dolphin plug-in (command-services-dolphin.so) loaded as Dolphin loads it (KPluginFactory,
//  with its embedded metadata) and asked for its actions with KFileItems of real files, so its menu
//  building and its activation (a service, and the launch of a selected applet bundle) are tested
//  without Dolphin, a display or root: the same cases as the GNOME Files plug-in's test
//  (../Nautilus/command-services-nautilus-test.c). The services list is written into a temporary
//  data folder (XDG_DATA_HOME), its program a script that writes its arguments to a file. Runs on
//  Qt's offscreen platform.
//
//  Usage: command-services-dolphin-test <path of command-services-dolphin.so>
//

#include <KAbstractFileItemActionPlugin>
#include <KFileItem>
#include <KFileItemListProperties>
#include <KPluginFactory>
#include <KPluginMetaData>
#include <QAction>
#include <QApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMenu>
#include <QTemporaryDir>
#include <QThread>
#include <QWidget>
#include <cstdio>
#include <sys/stat.h>

namespace
{

int sFailures = 0;
int sChecks = 0;
QString sWork;			// the files, the program and its output
QString sOutput;		// what the program was started with
KAbstractFileItemActionPlugin *sPlugin = nullptr;
QWidget *sParent = nullptr;

void
check(bool inPassed, const char *inWhat, const QString &inDetail = QString())
{
	sChecks++;
	if(inPassed)
	{
		std::printf("ok %d %s\n", sChecks, inWhat);
		return;
	}
	sFailures++;
	std::printf("not ok %d %s %s\n", sChecks, inWhat, qPrintable(inDetail));
}

void
write_file(const QString &inPath, const QByteArray &inText, bool inExecutable = false)
{
	QFile file(inPath);
	bool written = file.open(QIODevice::WriteOnly | QIODevice::Truncate) && (file.write(inText) == inText.size());
	file.close();
	if(written && inExecutable)
		written = file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner | QFileDevice::ReadGroup | QFileDevice::ExeGroup);
	if(!written)
	{
		std::fprintf(stderr, "cannot write %s\n", qPrintable(inPath));
		std::exit(1);
	}
}

KFileItem
folder_item(const QString &inPath)
{
	QDir().mkpath(inPath);
	return KFileItem(QUrl::fromLocalFile(inPath), QStringLiteral("inode/directory"), S_IFDIR);
}

KFileItem
file_item(const QString &inPath, const QString &inMimeType)
{
	write_file(inPath, "x\n");
	return KFileItem(QUrl::fromLocalFile(inPath), inMimeType, S_IFREG);
}

QList<QAction *>
actions_for(const KFileItemList &inItems)
{
	return sPlugin->actions(KFileItemListProperties(inItems), sParent);
}

// The "Services" action among inActions, or nullptr
QAction *
services_action(const QList<QAction *> &inActions)
{
	for(QAction *action : inActions)
	{
		if(action->text() == QStringLiteral("Services"))
			return action;
	}
	return nullptr;
}

// The texts of the "Services" action's submenu, joined with "|"; "" for no such action
QString
services_labels(const QList<QAction *> &inActions)
{
	QAction *services = services_action(inActions);
	if((services == nullptr) || (services->menu() == nullptr))
		return QString();
	QStringList labels;
	for(QAction *action : services->menu()->actions())
		labels.append(action->text());
	return labels.join(QLatin1Char('|'));
}

// The file inPath once it is there (the program writes it when started), up to 5 seconds
QByteArray
wait_for(const QString &inPath)
{
	for(int tenths = 0; tenths < 50; tenths++)
	{
		QFile file(inPath);
		if(file.open(QIODevice::ReadOnly))
			return file.readAll();
		QThread::msleep(100);
	}
	return QByteArray();
}

void
test_items_for_the_selection()
{
	const KFileItem folder = folder_item(sWork + QStringLiteral("/a folder"));
	const KFileItem text = file_item(sWork + QStringLiteral("/notes.txt"), QStringLiteral("text/plain"));
	const KFileItem png = file_item(sWork + QStringLiteral("/picture.png"), QStringLiteral("image/png"));

	QString labels = services_labels(actions_for({ folder }));
	check(labels == QStringLiteral("Any File Or Folder|Search Here"), "a folder: the lists in name order", labels);
	// "&" doubled in the action's text, as Qt reads one as a shortcut mark; "_" as it is
	labels = services_labels(actions_for({ text }));
	check(labels == QStringLiteral("Any File Or Folder|Text_Tool && More"), "a text file (\"&\" doubled)", labels);
	labels = services_labels(actions_for({ text, png }));
	check(labels == QStringLiteral("Any File Or Folder"), "a text file and an image: the text tool takes text only", labels);

	// Nothing fits: no Services item at all
	const QString listPath = sWork + QStringLiteral("/data/command/services/com.example.Any.services");
	QFile list(listPath);
	list.open(QIODevice::ReadOnly);
	const QByteArray kept = list.readAll();
	list.close();
	QFile::remove(listPath);
	check(actions_for({ png }).isEmpty(), "nothing fits: no action");
	write_file(listPath, kept);
}

void
test_choosing_a_service_starts_the_applet()
{
	const QString folderPath = sWork + QStringLiteral("/a folder");
	QAction *services = services_action(actions_for({ folder_item(folderPath) }));
	QAction *searchHere = nullptr;
	if(services != nullptr)
	{
		for(QAction *action : services->menu()->actions())
		{
			if(action->text() == QStringLiteral("Search Here"))
				searchHere = action;
		}
	}
	check(searchHere != nullptr, "the folder's Search Here service");
	if(searchHere == nullptr)
		return;
	QFile::remove(sOutput);
	searchHere->trigger();
	const QByteArray started = wait_for(sOutput);
	const QByteArray expected = "--command-service\nfind.new\n" + QUrl::fromLocalFile(folderPath).toEncoded() + "\n";
	check(started == expected, "choosing it starts the applet with the command and the folder's URI", QString::fromUtf8(started));
}

void
make_bundle(const QString &inPath, const QString &inName, bool inFlat, const QByteArray &inScript)
{
	const QString programFolder = inFlat ? inPath : inPath + QStringLiteral("/Contents/Linux");
	QDir().mkpath(programFolder);
	write_file(inFlat ? inPath + QStringLiteral("/Info.plist") : inPath + QStringLiteral("/Contents/Info.plist"), "<plist/>\n");
	write_file(programFolder + QLatin1Char('/') + inName, inScript, true);
}

void
test_an_applet_bundle_gets_a_launch_item()
{
	const QString launched = sWork + QStringLiteral("/launched");
	const QByteArray script = "#!/bin/sh\nprintf 'arguments:%s\\n' \"$#\" > '" + launched.toUtf8() + ".part' && mv '" + launched.toUtf8() + ".part' '" + launched.toUtf8() + "'\n";
	const QString bundlePath = sWork + QStringLiteral("/Demo.app");
	make_bundle(bundlePath, QStringLiteral("Demo"), false, script);
	const KFileItem bundle = folder_item(bundlePath);

	// The one selected item: "Launch Demo" first, then the folder's services
	QList<QAction *> actions = actions_for({ bundle });
	check((actions.count() == 2) && (actions.first()->text() == QStringLiteral("Launch Demo")), "an applet bundle: Launch Demo first",
		  actions.isEmpty() ? QString() : actions.first()->text());
	const QString labels = services_labels(actions);
	check(labels == QStringLiteral("Any File Or Folder|Search Here"), "then its services as a folder's", labels);
	check(!actions.isEmpty() && (actions.first()->icon().name() == QStringLiteral("system-run")),
		  "no icon of its own: the theme's system-run", actions.isEmpty() ? QString() : actions.first()->icon().name());
	if(!actions.isEmpty())
	{
		QFile::remove(launched);
		actions.first()->trigger();
		const QByteArray started = wait_for(launched);
		check(started == "arguments:0\n", "Launch starts the program with no arguments", QString::fromUtf8(started));
	}

	// With another item selected: no launch action
	const KFileItem folder = folder_item(sWork + QStringLiteral("/a folder"));
	actions = actions_for({ bundle, folder });
	check((actions.count() == 1) && (actions.first()->text() == QStringLiteral("Services")), "two items: no launch action");

	// "&" in a name doubled, as Qt reads one as a shortcut mark; "_" as it is
	const QString toolPath = sWork + QStringLiteral("/My_Tool & Co.app");
	make_bundle(toolPath, QStringLiteral("My_Tool & Co"), false, "#!/bin/sh\n");
	actions = actions_for({ folder_item(toolPath) });
	check(!actions.isEmpty() && (actions.first()->text() == QStringLiteral("Launch My_Tool && Co")), "a name with \"_\" and \"&\"",
		  actions.isEmpty() ? QString() : actions.first()->text());

	// The flat layout: Info.plist, the program and the icon at the top
	const QString flatPath = sWork + QStringLiteral("/Flat.app");
	make_bundle(flatPath, QStringLiteral("Flat"), true, "#!/bin/sh\n");
	write_file(flatPath + QStringLiteral("/Info.plist"), "<plist version=\"1.0\"><dict><key>CFBundleIconFile</key><string>AppIcon</string></dict></plist>\n");
	write_file(flatPath + QStringLiteral("/AppIcon.svg"),
			   "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\"><rect width=\"16\" height=\"16\" fill=\"#ffa640\"/></svg>\n");
	actions = actions_for({ folder_item(flatPath) });
	check((actions.count() == 2) && (actions.first()->text() == QStringLiteral("Launch Flat")), "the flat layout");
	check(!actions.isEmpty() && actions.first()->icon().name().isEmpty() && !actions.first()->icon().pixmap(16, 16).isNull(),
		  "its own icon, drawn from its SVG file");

	// A folder named .app without a Linux program: no launch action
	actions = actions_for({ folder_item(sWork + QStringLiteral("/MacOnly.app")) });
	check((actions.count() == 1) && (actions.first()->text() == QStringLiteral("Services")), "a .app folder with no Linux program");
}

void
write_lists()
{
	const QString folder = sWork + QStringLiteral("/data/command/services");
	QDir().mkpath(folder);
	const QString program = sWork + QStringLiteral("/Applet");
	sOutput = sWork + QStringLiteral("/started");
	write_file(program, "#!/bin/sh\nprintf '%s\\n' \"$@\" > '" + sOutput.toUtf8() + ".part' && mv '" + sOutput.toUtf8() + ".part' '" + sOutput.toUtf8() + "'\n", true);
	write_file(folder + QStringLiteral("/com.example.Find.services"),
			   "[Applet]\nVersion=1\nApplication=com.example.Find\nName=Find\nProgram=" + program.toUtf8() + "\n\n"
			   "[Service 0]\nTitle=Search Here\nCommand=find.new\nMimeTypes=inode/directory;\n");
	write_file(folder + QStringLiteral("/com.example.Any.services"),
			   "[Applet]\nVersion=1\nApplication=com.example.Any\nName=Any\nProgram=" + program.toUtf8() + "\n\n"
			   "[Service 0]\nTitle=Any File Or Folder\nCommand=any.run\nMimeTypes=application/octet-stream;inode/directory;\n"
			   "[Service 1]\nTitle=Text_Tool & More\nCommand=text.run\nMimeTypes=text/plain;\n");
}

} // namespace

int
main(int argc, char *argv[])
{
	if(argc < 2)
	{
		std::fprintf(stderr, "usage: %s <command-services-dolphin.so>\n", argv[0]);
		return 2;
	}
	QTemporaryDir work(QDir::tempPath() + QStringLiteral("/command-services-dolphin-test-XXXXXX"));
	if(!work.isValid())
	{
		std::fprintf(stderr, "no temporary folder\n");
		return 1;
	}
	sWork = work.path();
	qputenv("XDG_DATA_HOME", QFile::encodeName(sWork + QStringLiteral("/data"))); // before GLib reads it
	qputenv("QT_QPA_PLATFORM", "offscreen");
	write_lists();
	QApplication application(argc, argv);
	sParent = new QWidget();

	// An absolute path: KPluginMetaData looks for a relative one beside the test program and in Qt's
	// library paths only, not in the current folder (build.sh <relative output folder>)
	const KPluginMetaData metaData(QFileInfo(QFile::decodeName(argv[1])).absoluteFilePath());
	if(!metaData.isValid())
	{
		std::fprintf(stderr, "no plug-in metadata in %s\n", argv[1]);
		return 1;
	}
	check(metaData.mimeTypes().contains(QStringLiteral("inode/directory")) && metaData.mimeTypes().contains(QStringLiteral("application/octet-stream")),
		  "the metadata offers it for files and folders", metaData.mimeTypes().join(QLatin1Char(',')));
	const auto result = KPluginFactory::instantiatePlugin<KAbstractFileItemActionPlugin>(metaData, sParent);
	if(!result)
	{
		std::fprintf(stderr, "cannot load %s: %s\n", argv[1], qPrintable(result.errorString));
		return 1;
	}
	sPlugin = result.plugin;

	test_items_for_the_selection();
	test_choosing_a_service_starts_the_applet();
	test_an_applet_bundle_gets_a_launch_item();
	std::printf("1..%d\n", sChecks);
	delete sParent;
	return (sFailures == 0) ? 0 : 1;
}
