import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Keep monitoring when the window is closed; the Dock icon reopens it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct PingWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var monitor = Monitor()
    private static let activity = ProcessInfo.processInfo.beginActivity(
        options: .userInitiatedAllowingIdleSystemSleep, reason: "Pinging hosts")

    init() { _ = Self.activity }

    var body: some Scene {
        WindowGroup("PingWatch") {
            ContentView().environmentObject(monitor)
        }
        .windowResizability(.contentMinSize)
    }
}
