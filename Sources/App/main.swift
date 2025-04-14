import AppKit

// Initialize the shared NSApplication instance
let app = NSApplication.shared

// Create and set the application delegate
let delegate = AppDelegate()
app.delegate = delegate

// Activate the application and bring it to the foreground
NSApp.activate(ignoringOtherApps: true)

// Run the application's main event loop
// This call doesn't return until the application terminates
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
