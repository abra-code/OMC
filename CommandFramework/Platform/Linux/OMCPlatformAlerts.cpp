//
//  OMCPlatformAlerts.cpp (Linux)
//  Abracode
//
//  The Linux implementation of OMCPlatformShowAlert and OMCPlatformShowNotice (Platform/OMCAlerts.h;
//  named apart from the portable OMCAlerts.cpp, as the Linux build's shims share one folder):
//  libadwaita's AdwAlertDialog, over the application's active window, or as a window of its own
//  when there is none.
//  - An alert waits for its answer in a nested GLib main loop (OMCModalLoop.h, so a quit ends the
//    wait: no answer; so does the window it is over going away). Its buttons are, left to right,
//    the other, the alternate and the default, as on macOS, when they fit side by side; when they
//    do not (often three buttons in an alert of its own), libadwaita stacks them, the default on
//    top. Enter answers the default, Escape the alternate (the default when there is no
//    alternate), as CFUserNotification's alert does. The level shows in nothing: libadwaita's
//    alerts have no icon (the macOS levels are icons).
//  - A notice is shown and left: it does not wait.
//  Without GTK (no display, or a process that has not made its application) neither can be shown:
//  the alert answers "no response" and both log their text.
//  Main thread only.
//

#include "OMCAlerts.h"
#include "Linux/OMCModalLoop.h"
#include "OMCLog.h"
#include "ACFString.h"
#include <adwaita.h>
#include <string>

namespace
{

const char *kDefaultResponse = "default";
const char *kAlternateResponse = "alternate";
const char *kOtherResponse = "other";

AdwDialog *
MakeAlertDialog(CFStringRef inHeader, CFStringRef inMessage)
{
	std::string header = ACFStringToUTF8(inHeader);
	std::string message = ACFStringToUTF8(inMessage);
	return adw_alert_dialog_new(header.c_str(), message.empty() ? nullptr : message.c_str());
}

void
AddResponse(AdwDialog *inDialog, const char *inID, CFStringRef inTitle)
{
	std::string title = ACFStringToUTF8(inTitle);
	adw_alert_dialog_add_response(ADW_ALERT_DIALOG(inDialog), inID, title.c_str());
}

struct AlertWait
{
	GMainLoop *loop {nullptr};
	std::string response;
	bool removed {false};
};

void
OnAlertResponse(AdwAlertDialog *, const char *inResponse, gpointer inWait)
{
	AlertWait *wait = static_cast<AlertWait *>(inWait);
	wait->response = (inResponse != nullptr) ? inResponse : "";
	if(g_main_loop_is_running(wait->loop))
		g_main_loop_quit(wait->loop);
}

// The dialog was taken out of its window without an answer: its parent window was destroyed (the
// dialog emits neither "response" nor "closed" then). Nobody is left to answer, so the wait ends
// (no response).
void
OnAlertParentChanged(GtkWidget *inDialog, GParamSpec *, gpointer inWait)
{
	if(gtk_widget_get_parent(inDialog) != nullptr)
		return; // put into a window, not taken out
	AlertWait *wait = static_cast<AlertWait *>(inWait);
	wait->removed = true;
	if(g_main_loop_is_running(wait->loop))
		g_main_loop_quit(wait->loop);
}

} // namespace

OMCAlertResponse
OMCPlatformShowAlert(OMCAlertLevel inLevel, CFStringRef inHeader, CFStringRef inMessage,
					CFStringRef inDefaultButton, CFStringRef inAlternateButton, CFStringRef inOtherButton)
{
	(void)inLevel;
	if(!gtk_is_initialized())
	{
		OMCLogMessage("alert not shown (no GTK): %s: %s", OMCLogCString(inHeader).c_str(), OMCLogCString(inMessage).c_str());
		return kOMCAlertNoResponse;
	}

	AdwDialog *dialog = MakeAlertDialog(inHeader, inMessage);
	g_object_ref_sink(dialog); // ours until the answer is read (the response signal closes it)
	if(inOtherButton != nullptr)
		AddResponse(dialog, kOtherResponse, inOtherButton);
	if(inAlternateButton != nullptr)
		AddResponse(dialog, kAlternateResponse, inAlternateButton);
	AddResponse(dialog, kDefaultResponse, (inDefaultButton != nullptr) ? inDefaultButton : CFSTR("OK"));
	adw_alert_dialog_set_response_appearance(ADW_ALERT_DIALOG(dialog), kDefaultResponse, ADW_RESPONSE_SUGGESTED);
	adw_alert_dialog_set_default_response(ADW_ALERT_DIALOG(dialog), kDefaultResponse);
	adw_alert_dialog_set_close_response(ADW_ALERT_DIALOG(dialog), (inAlternateButton != nullptr) ? kAlternateResponse : kDefaultResponse);

	AlertWait wait;
	wait.loop = g_main_loop_new(nullptr, FALSE);
	gulong responseHandler = g_signal_connect(dialog, "response", G_CALLBACK(OnAlertResponse), &wait);
	gulong parentHandler = g_signal_connect(dialog, "notify::parent", G_CALLBACK(OnAlertParentChanged), &wait);
	adw_dialog_present(dialog, GTK_WIDGET(OMCModalParentWindow()));
	OMCRunModalLoop(wait.loop); // returns at the answer, or with no response when its window goes or a quit ends it
	g_signal_handler_disconnect(dialog, responseHandler);
	g_signal_handler_disconnect(dialog, parentHandler);
	if(wait.response.empty() && !wait.removed)
		adw_dialog_force_close(dialog); // ended without an answer: the dialog goes too
	g_object_unref(dialog);
	g_main_loop_unref(wait.loop);

	if(wait.response == kDefaultResponse)
		return kOMCAlertDefaultResponse;
	if(wait.response == kAlternateResponse)
		return kOMCAlertAlternateResponse;
	if(wait.response == kOtherResponse)
		return kOMCAlertOtherResponse;
	return kOMCAlertNoResponse;
}

void
OMCPlatformShowNotice(CFStringRef inHeader, CFStringRef inMessage, CFStringRef inButton, CFURLRef inIconURL)
{
	(void)inIconURL; // libadwaita's alerts have no icon
	if(!gtk_is_initialized())
	{
		OMCLogMessage("notice not shown (no GTK): %s: %s", OMCLogCString(inHeader).c_str(), OMCLogCString(inMessage).c_str());
		return;
	}
	AdwDialog *dialog = MakeAlertDialog(inHeader, inMessage);
	AddResponse(dialog, kDefaultResponse, (inButton != nullptr) ? inButton : CFSTR("OK"));
	adw_alert_dialog_set_default_response(ADW_ALERT_DIALOG(dialog), kDefaultResponse);
	adw_alert_dialog_set_close_response(ADW_ALERT_DIALOG(dialog), kDefaultResponse);
	adw_dialog_present(dialog, GTK_WIDGET(OMCModalParentWindow())); // shown and left: the dialog closes itself at its answer
}
