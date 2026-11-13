//
//  OMCTerminalLauncher.cpp (Linux)
//  Abracode
//
//  EXECUTION_MODE exe_terminal and exe_iterm on Linux: the command line runs in a new window of a
//  terminal program found on the system, as Terminal runs it on macOS: in the user's shell, which
//  then stays open for more commands (an interactive shell, exited by the user).
//
//  The terminal is the first of these found on PATH, each given the command its own way:
//    xdg-terminal-exec      the freedesktop.org proposal for "the user's terminal": the command as
//                           its arguments (Fedora, Ubuntu and others ship it)
//    x-terminal-emulator    Debian's choice of terminal (update-alternatives): -e and the command
//    gnome-terminal, ptyxis, kgx (GNOME Console): -- and the command
//    konsole, xterm         -e and the command
//    xfce4-terminal         -x and the command
//  A system with none logs that and runs nothing, as macOS does without Terminal.
//
//  exe_iterm has no iTerm here: it runs as exe_terminal (ITERM_SHELL_PATH is not used, as on
//  macOS). Linux terminals open a new window when started this way, so openInNewWindow is always
//  true in effect; a new window comes to the front, so bringToFront needs nothing.
//
//  The terminal starts in the home folder, as a new Terminal window does on macOS.
//
//  Main thread only (OMCTerminalLauncher.h).
//

#include "OMCTerminalLauncher.h"
#include "OMCLinuxTerminal.h"
#include "OMCLog.h"
#include "ACFString.h"
#include <glib.h>
#include <pwd.h>
#include <unistd.h>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace
{

// The user's shell: $SHELL, else the account's, else /bin/sh
std::string
UserShell()
{
	const char *shell = getenv("SHELL");
	if((shell != nullptr) && (shell[0] == '/'))
		return shell;
	struct passwd *account = getpwuid(getuid());
	if((account != nullptr) && (account->pw_shell != nullptr) && (account->pw_shell[0] == '/'))
		return account->pw_shell;
	return "/bin/sh";
}

void
RunInTerminal(CFStringRef inCommand, const std::string &inShell)
{
	if(inCommand == nullptr)
		return;

	std::vector<std::string> arguments = OMCLinuxTerminalArguments(ACFStringToUTF8(inCommand), inShell);
	if(arguments.empty())
	{
		OMCLogMessage("no terminal program found to run the command in (looked for %s on PATH)", OMCLinuxTerminalNames());
		return;
	}

	std::vector<char *> argv;
	for(std::string &oneArgument : arguments)
		argv.push_back(oneArgument.data());
	argv.push_back(nullptr);

	// Not reaped by us: GLib's intermediate child leaves the terminal to init, so it outlives the
	// applet as a Terminal window does
	GError *error = nullptr;
	// In the home folder, where a new Terminal window starts on macOS (the applet's own working
	// folder is often / when the desktop started it)
	gboolean started = g_spawn_async(g_get_home_dir(), argv.data(), nullptr, G_SPAWN_STDOUT_TO_DEV_NULL, nullptr, nullptr, nullptr, &error);
	if(!started)
	{
		OMCLogMessage("could not start the terminal %s: %s", arguments[0].c_str(), (error != nullptr) ? error->message : "unknown error");
		g_clear_error(&error);
	}
}

} // namespace

const char *
OMCLinuxTerminalNames()
{
	return "xdg-terminal-exec, x-terminal-emulator, gnome-terminal, ptyxis, kgx, konsole, xfce4-terminal, xterm";
}

std::vector<std::string>
OMCLinuxTerminalArguments(const std::string &inCommand, const std::string &inShell)
{
	// What the terminal runs: the shell runs the command, then replaces itself with an interactive
	// shell, so the window stays open with the command's output above the prompt. The command is
	// the shell's own text (the engine wrote its environment setup in this shell's syntax).
	std::string quotedShell;
	{
		gchar *quoted = g_shell_quote(inShell.c_str());
		quotedShell = quoted;
		g_free(quoted);
	}
	std::vector<std::string> command { inShell, "-c", inCommand + "\nexec " + quotedShell + " -i" };

	struct Terminal
	{
		const char *name;
		const char *option; // before the command; nullptr: the command follows the program
	};
	static const Terminal sTerminals[] = {
		{ "xdg-terminal-exec", nullptr },
		{ "x-terminal-emulator", "-e" },
		{ "gnome-terminal", "--" },
		{ "ptyxis", "--" },
		{ "kgx", "--" },
		{ "konsole", "-e" },
		{ "xfce4-terminal", "-x" },
		{ "xterm", "-e" },
	};
	for(const Terminal &oneTerminal : sTerminals)
	{
		gchar *path = g_find_program_in_path(oneTerminal.name);
		if(path == nullptr)
			continue;
		std::vector<std::string> arguments { path };
		g_free(path);
		if(oneTerminal.option != nullptr)
			arguments.push_back(oneTerminal.option);
		arguments.insert(arguments.end(), command.begin(), command.end());
		return arguments;
	}
	return {};
}

void
OMCExecuteInTerminal(CFStringRef inCommand, bool openInNewWindow, bool bringToFront)
{
	(void)openInNewWindow;
	(void)bringToFront;
	RunInTerminal(inCommand, UserShell());
}

void
OMCExecuteInITerm(CFStringRef inCommand, CFStringRef inShellPath, bool openInNewWindow, bool bringToFront)
{
	// As on macOS, ITERM_SHELL_PATH is not used: the command runs in the user's shell, whose
	// syntax the engine wrote the environment setup in (OMCIsShDefaultInITerm)
	(void)inShellPath;
	OMCExecuteInTerminal(inCommand, openInNewWindow, bringToFront);
}

// The syntax of the shell the command runs in (UserShell): only csh and tcsh differ for the
// environment setup. Not IsShDefaultLoginShell, which reads only $SHELL: with $SHELL unset and a
// csh account, the setup would be written for sh and run in csh.
bool
OMCIsShDefaultInTerminal()
{
	return (strstr(UserShell().c_str(), "csh") == nullptr);
}

bool
OMCIsShDefaultInITerm()
{
	return OMCIsShDefaultInTerminal();
}
