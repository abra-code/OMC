//
//  command-services-dolphin.cpp
//  Command Workshop file manager services
//
//  The Dolphin (KDE Plasma's file manager; KIO 6 file item actions) plug-in, the counterpart of the
//  GNOME Files and Thunar ones (../Nautilus, ../Thunar): a "Services" submenu in the right-click
//  menu, holding the Command applets' file services that fit the selection (../command-services-core.h),
//  or the folder shown when the click is on its background. Choosing one starts the applet with
//  "--command-service <command> <file URIs>"; the applet runs only a command it declares, and a
//  running applet takes the request over from the program started. The lists are read again each
//  time Dolphin makes the menu: a few small files, and nothing to watch.
//
//  A selected applet bundle (a <Name>.app folder with a Linux program) also gets "Launch <Name>",
//  ahead of "Services": it starts the applet as its desktop entry would. The item shows the applet's
//  own icon (command_applet_icon), else the icon theme's system-run.
//
//  Installed as root into KIO's plug-in folder (<Qt plug-in folder>/kf6/kfileitemaction), which
//  Dolphin reads each time it makes a menu; Dolphin's Settings, Context Menu, lists it by its name
//  and can turn it off.
//
//  Where Dolphin differs from GNOME Files and Thunar (KIO 6.13):
//  - KIO asks a plug-in only when the selection has a common MIME type (application/octet-stream
//    for files of different types), so a folder and a file selected together get no services here.
//  - A click on a folder's background gives the folder as the one item, as a selection would: inside
//    an applet bundle, "Launch <Name>" shows there too.
//  - The actions are parented to the widget KIO gives (Dolphin's main window), as KIO asks; KIO
//    does not delete them after the menu, so each menu's few actions live until the window closes.
//    KIO 6.32's KFileItemActionPluginV2 (actionsForParent) is the way out, when Debian has it.
//

// GLib first, and Qt with no keywords: GLib's headers use "signals" as a name, which Qt's keyword
// macro would turn into "public"
#include "command-services-core.h"

#include <KAbstractFileItemActionPlugin>
#include <KFileItem>
#include <KFileItemListProperties>
#include <KPluginFactory>
#include <QAction>
#include <QFile>
#include <QIcon>
#include <QMenu>
#include <QWidget>
#include <memory>

namespace
{

// A command line as GLib takes it, freed with the action that holds it
using CommandLine = std::shared_ptr<char *>;

CommandLine
adopt_command_line(char **inCommandLine)
{
	return CommandLine(inCommandLine, [](char **inLine) { g_strfreev(inLine); });
}

// A menu text for inText: Qt reads "&" as the mark of a keyboard shortcut, so each one is doubled
QString
menu_text(const char *inText)
{
	QString text = QString::fromUtf8(inText);
	text.replace(QLatin1Char('&'), QStringLiteral("&&"));
	return text;
}

// An action that starts inCommandLine when chosen
QAction *
start_action(const QString &inText, CommandLine inCommandLine, QObject *inParent)
{
	QAction *action = new QAction(inText, inParent);
	QObject::connect(action, &QAction::triggered, action, [inCommandLine]() {
		GError *error = nullptr;
		if(!g_spawn_async(nullptr, inCommandLine.get(), nullptr, G_SPAWN_STDOUT_TO_DEV_NULL, nullptr, nullptr, nullptr, &error))
		{
			g_warning("Command services: %s could not be started: %s", inCommandLine.get()[0], (error != nullptr) ? error->message : "unknown error");
			g_clear_error(&error);
		}
	});
	return action;
}

// The local path of an item, as the file system names it, or empty (a remote file has none)
QByteArray
item_path(const KFileItem &inItem)
{
	bool isLocal = false;
	const QUrl url = inItem.mostLocalUrl(&isLocal);
	if(!isLocal || !url.isLocalFile())
		return QByteArray();
	return QFile::encodeName(url.toLocalFile());
}

} // namespace

class CommandServicesPlugin : public KAbstractFileItemActionPlugin
{
	Q_OBJECT

public:
	CommandServicesPlugin(QObject *inParent, const QVariantList &inArguments)
		: KAbstractFileItemActionPlugin(inParent)
	{
		Q_UNUSED(inArguments);
	}

	// "Launch <Name>" for an applet bundle, then "Services"; for a click on the folder's
	// background, Dolphin gives the folder shown as the one item
	QList<QAction *>
	actions(const KFileItemListProperties &inFileItemInfos, QWidget *inParentWidget) override
	{
		QList<QAction *> actions;
		const KFileItemList items = inFileItemInfos.items();
		QAction *launch = launch_action(items, inParentWidget);
		if(launch != nullptr)
			actions.append(launch);
		QAction *services = services_action(items, inParentWidget);
		if(services != nullptr)
			actions.append(services);
		return actions;
	}

private:
	// The "Services" item with a submenu of the services that fit the items, or nullptr when none
	// does (or an item is not a local file or folder)
	static QAction *
	services_action(const KFileItemList &inItems, QWidget *inParentWidget)
	{
		if(inItems.isEmpty())
			return nullptr;
		GPtrArray *types = g_ptr_array_new_with_free_func(g_free);
		GPtrArray *uris = g_ptr_array_new_with_free_func(g_free);
		QAction *result = nullptr;
		bool allLocal = true;
		for(const KFileItem &item : inItems)
		{
			const QByteArray path = item_path(item);
			char *uri = path.isEmpty() ? nullptr : g_filename_to_uri(path.constData(), nullptr, nullptr);
			if(uri == nullptr)
			{
				allLocal = false; // a service runs on local files only
				break;
			}
			// The URI of the path, not of the item's URL: a folder mounted by KIO under another
			// scheme has a local path, but the applet refuses anything but a file URI
			g_ptr_array_add(uris, uri);
			const QByteArray type = item.isDir() ? QByteArray("inode/directory") : item.mimetype().toUtf8();
			g_ptr_array_add(types, g_strdup(type.constData()));
		}
		if(allLocal)
		{
			char *folder = command_services_folder();
			GPtrArray *services = command_services_load(folder);
			g_free(folder);
			QMenu *submenu = nullptr;
			for(guint i = 0; i < services->len; i++)
			{
				const CommandService *service = static_cast<const CommandService *>(g_ptr_array_index(services, i));
				if(!command_service_fits(service, reinterpret_cast<const char *const *>(types->pdata), types->len))
					continue;
				if(submenu == nullptr)
					submenu = new QMenu(inParentWidget);
				CommandLine commandLine = adopt_command_line(command_service_command_line(service, reinterpret_cast<const char *const *>(uris->pdata), uris->len));
				QAction *action = start_action(menu_text(service->title), commandLine, submenu);
				action->setToolTip(QString::fromUtf8(service->applet_name));
				submenu->addAction(action);
			}
			g_ptr_array_unref(services);
			if(submenu != nullptr)
			{
				result = new QAction(QStringLiteral("Services"), inParentWidget);
				result->setMenu(submenu);
			}
		}
		g_ptr_array_unref(types);
		g_ptr_array_unref(uris);
		return result;
	}

	// "Launch <Name>" when the one item is an applet bundle with a Linux program
	// (command_applet_program), or nullptr. It starts the program as the desktop entry does, with
	// no arguments; a running applet takes the launch over and comes to the front.
	static QAction *
	launch_action(const KFileItemList &inItems, QWidget *inParentWidget)
	{
		if((inItems.count() != 1) || !inItems.first().isDir())
			return nullptr;
		const QByteArray path = item_path(inItems.first());
		if(path.isEmpty())
			return nullptr;
		char *name = nullptr;
		char *program = command_applet_program(path.constData(), &name);
		if(program == nullptr)
			return nullptr;
		// A file name need not be UTF-8
		char *displayName = g_filename_display_name(name);
		g_free(name);
		char *text = g_strdup_printf("Launch %s", displayName);
		g_free(displayName);
		char **commandLine = g_new0(char *, 2);
		commandLine[0] = program;
		QAction *action = start_action(menu_text(text), adopt_command_line(commandLine), inParentWidget);
		g_free(text);
		// The applet's own icon, as Open With shows an application's; the theme's "run" icon for an
		// applet with no PNG or SVG one
		char *icon = command_applet_icon(path.constData());
		action->setIcon((icon != nullptr) ? QIcon(QFile::decodeName(icon)) : QIcon::fromTheme(QStringLiteral("system-run")));
		g_free(icon);
		return action;
	}
};

K_PLUGIN_CLASS_WITH_JSON(CommandServicesPlugin, "command-services-dolphin.json")

#include "command-services-dolphin.moc"
