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
                .companionWindowFrame()
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


/// Size of the companion window. The default is large enough to show the whole dashboard
/// (header, tabs, schedule card, and the metric grid in two rows) and most settings tabs
/// without scrolling or resizing, shrunk to fit smaller screens.
enum CompanionWindowLayout {
    static let minimumSize = CGSize(width: 680, height: 620)
    static let idealSize = CGSize(width: 1000, height: 860)

    /// Bump when `idealSize` changes so existing users get the new size once, after which
    /// their own resizing is restored as usual.
    private static let layoutVersion = 2
    private static let layoutVersionKey = "companionWindowLayoutVersion"

    /// `idealSize` clamped to the screen's usable area, never below `minimumSize`.
    static func preferredContentSize(on screen: NSScreen?) -> CGSize {
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else {
            return idealSize
        }
        // Leave room for the title bar and a small margin around the window.
        let width = min(idealSize.width, visible.width - 40)
        let height = min(idealSize.height, visible.height - 60)
        return CGSize(
            width: max(minimumSize.width, width),
            height: max(minimumSize.height, height),
        )
    }

    /// Applies the minimum size, and resizes a window restored at an older, smaller default once.
    static func configure(_ window: NSWindow) {
        window.contentMinSize = minimumSize
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: layoutVersionKey) < layoutVersion else {
            return
        }
        defaults.set(layoutVersion, forKey: layoutVersionKey)
        window.setContentSize(preferredContentSize(on: window.screen))
        window.center()
    }
}


extension View {
    /// Minimum and initial size for a companion window. On macOS a window opens at its content's
    /// ideal size, so the ideal values set the default for new windows; the configurator updates
    /// windows macOS restores at an older size.
    func companionWindowFrame() -> some View {
        let preferred = CompanionWindowLayout.preferredContentSize(on: NSScreen.main)
        return frame(
            minWidth: CompanionWindowLayout.minimumSize.width,
            idealWidth: preferred.width,
            maxWidth: .infinity,
            minHeight: CompanionWindowLayout.minimumSize.height,
            idealHeight: preferred.height,
            maxHeight: .infinity,
        )
        .background(CompanionWindowConfigurator())
    }
}


/// Hands the hosting `NSWindow` to `CompanionWindowLayout` once the view is in a window.
private struct CompanionWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowObservingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowObservingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else {
                return
            }
            // Defer until SwiftUI has finished its own initial sizing and frame restoration.
            DispatchQueue.main.async {
                CompanionWindowLayout.configure(window)
            }
        }
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
