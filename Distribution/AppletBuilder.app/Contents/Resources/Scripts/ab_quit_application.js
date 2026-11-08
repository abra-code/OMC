// ab_quit_application.js - asks a running application to quit, as its Quit menu item would.
//
// Usage: /usr/bin/osascript -l JavaScript ab_quit_application.js <pid>
//
// NSRunningApplication's terminate sends the application the ordinary quit request, so it runs
// its own quit handling (an OMC applet's app.will.terminate, a question about unsaved work) and
// may decline. Addressed by process id, so of two copies of one applet only the one asked about
// is touched. Prints "sent", "gone" (no such application) or "refused"; the caller waits for the
// process to end.

ObjC.import('AppKit');

function run(argv) {
    const pid = parseInt(argv[0], 10);
    if (!(pid > 0)) {
        return 'usage: ab_quit_application.js <pid>';
    }
    const app = $.NSRunningApplication.runningApplicationWithProcessIdentifier(pid);
    if (app.isNil()) {
        return 'gone';
    }
    return app.terminate ? 'sent' : 'refused';
}
