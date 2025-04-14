import AppKit
import Metal
import AVFoundation

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // Main application window
    private var window: NSWindow?
    
    // Main view controller
    private var morphingViewController: MorphingViewController?
    
    // MARK: - Application Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await setupWindow()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean up resources if needed
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    // MARK: - Window Setup
    
    private func setupWindow() async {
        // Create a window with standard style and title bar
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        if let window = window {
            // Create the morphing view controller
            let morphingController = MorphingViewController()
            self.morphingViewController = morphingController
            
            // Set as the window's content
            window.contentViewController = morphingController
            
            // Configure the window
            window.center()
            window.title = "Metal Video Morpher"
            
            // Make the window key and order it front
            window.makeKeyAndOrderFront(nil)
            
            // Important: Move the window to the front to ensure it's visible
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = "Failed to create application window."
            alert.alertStyle = .critical
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
}
