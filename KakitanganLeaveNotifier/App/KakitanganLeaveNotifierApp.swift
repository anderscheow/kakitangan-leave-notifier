import AppKit
import GoogleSignIn
import SwiftUI


@main
struct KakitanganLeaveNotifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 680, minHeight: 620)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        .commands {
            // ⌘Q closes the window and leaves the app running in the menu bar instead of quitting.
            // Real quit lives in the status-bar menu. Termination is not intercepted at the app
            // level, so logout/restart/shutdown still terminate the app normally.
            CommandGroup(replacing: .appTermination) {
                Button("Close Window") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand()
            }
            CommandMenu("Kakitangan Companion") {
                ForEach(Array(DashboardSection.allCases.enumerated()), id: \.element) { index, section in
                    Button(section.rawValue) {
                        appDelegate.route(.section(section))
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }

                // ⇧⌘N keeps the system ⌘N "New Window" command intact.
                Button("New Meeting…") {
                    appDelegate.route(.newMeeting)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Check Now") {
                    Task { await BackgroundCheckRunner.run() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Test Notification") {
                    Task { try? await NotificationService.shared.sendTest() }
                }
            }
        }
    }

    /// Brings the app forward and switches the main window to the settings screen. Routed through a
    /// notification so it works regardless of which window/model instance is frontmost.
    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows
            .first { $0.isVisible && $0.styleMask.contains(.titled) }?
            .makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
    }
}


/// Menu item that stays in sync with Sparkle's `canCheckForUpdates`, matching Apple's recommended
/// SwiftUI pattern for driving update checks from the native menu bar.
private struct CheckForUpdatesCommand: View {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
