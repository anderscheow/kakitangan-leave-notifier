import AppKit
import SwiftUI
@preconcurrency import UserNotifications


@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var appVisibilityObserver: NSObjectProtocol?
    private var windowObservers: [NSObjectProtocol] = []
    private var configuredVisibility: AppVisibility = .menuBarAndDock
    private var leaveWatchModel: AppModel?
    private var leaveWatchWindow: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        GoogleCalendarService.configureSignIn()
        UNUserNotificationCenter.current().delegate = self
        appVisibilityObserver = NotificationCenter.default.addObserver(
            forName: .appVisibilityDidChange,
            object: nil,
            queue: .main,
        ) { [weak self] notification in
            guard let rawValue = notification.userInfo?["appVisibility"] as? String,
                  let visibility = AppVisibility(rawValue: rawValue) else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.configuredVisibility = visibility
                self.configureStatusItem(for: visibility)
                applyEffectiveActivationPolicy(for: visibility)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--test-notification") {
            NSApp.setActivationPolicy(.accessory)
            Task {
                try? await NotificationService.shared.sendTest()
                NSApp.terminate(nil)
            }
            return
        }
        if arguments.contains("--check-leaves") {
            NSApp.setActivationPolicy(.accessory)
            Task {
                await BackgroundCheckRunner.run()
                NSApp.terminate(nil)
            }
            return
        }
        _ = AppUpdater.shared
        configuredVisibility = ConfigurationStore().load().appVisibility
        configureStatusItem(for: configuredVisibility)
        observeWindowVisibility()
        Task.detached(priority: .utility) {
            LaunchAgentService.refreshInstalledApplicationIfNeeded()
        }
    }

    /// Keep the app alive in the menu bar when its window closes (via ⌘Q, ⌘W, or the red button).
    /// The real quit is the status-bar "Quit" item, which calls `NSApp.terminate` directly.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let appVisibilityObserver {
            NotificationCenter.default.removeObserver(appVisibilityObserver)
        }
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void,
    ) {
        completionHandler([.banner, .list, .sound])
    }

    private func observeWindowVisibility() {
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.willCloseNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
        ]
        windowObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    applyEffectiveActivationPolicy(for: self.configuredVisibility)
                }
            }
        }
    }

    private func configureStatusItem(for visibility: AppVisibility) {
        guard visibility.showsInMenuBar else {
            statusItem = nil
            return
        }
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "calendar.badge.clock",
            accessibilityDescription: "Kakitangan Companion",
        )
        item.button?.toolTip = "Kakitangan Companion"
        item.menu = makeStatusMenu()
        statusItem = item
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Open Kakitangan Companion",
            action: #selector(openLeaveWatch),
            keyEquivalent: "",
        )
        menu.addItem(.separator())
        for (index, section) in DashboardSection.allCases.enumerated() {
            let item = menu.addItem(
                withTitle: section.rawValue,
                action: #selector(showDashboardSection(_:)),
                keyEquivalent: "\(index + 1)",
            )
            item.representedObject = section.rawValue
        }
        let newMeetingItem = menu.addItem(
            withTitle: "New Meeting…",
            action: #selector(newMeeting),
            keyEquivalent: "n",
        )
        newMeetingItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Check now",
            action: #selector(checkNow),
            keyEquivalent: "",
        )
        menu.addItem(
            withTitle: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: "",
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Kakitangan Companion",
            action: #selector(quit),
            keyEquivalent: "",
        )
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func openLeaveWatch() {
        route(nil)
    }

    @objc private func showDashboardSection(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let section = DashboardSection(rawValue: rawValue) else {
            return
        }
        route(.section(section))
    }

    @objc private func newMeeting() {
        route(.newMeeting)
    }

    /// Brings the companion window forward and hands it `request`. Reuses whichever window is
    /// already on screen so shortcuts never spawn a second window backed by a separate model.
    func route(_ request: DashboardRequest?) {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let window = visibleCompanionWindow, window !== leaveWatchWindow {
            window.makeKeyAndOrderFront(nil)
            if let request {
                NotificationCenter.default.post(
                    name: .dashboardRequested,
                    object: nil,
                    userInfo: [DashboardRequest.userInfoKey: request],
                )
            }
            return
        }

        if let leaveWatchWindow {
            leaveWatchWindow.orderFrontRegardless()
            leaveWatchWindow.makeKey()
        } else {
            presentLeaveWatchWindow()
        }
        // This window's model is owned here, so update it directly rather than by broadcast.
        if let request {
            leaveWatchModel?.handle(request)
        }
    }

    private var visibleCompanionWindow: NSWindow? {
        NSApp.windows.first { window in
            window.styleMask.contains(.titled) && (window.isVisible || window.isMiniaturized)
        }
    }

    @objc private func checkNow() {
        Task {
            await BackgroundCheckRunner.run()
        }
    }

    @objc private func checkForUpdates() {
        AppUpdater.shared.checkForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func presentLeaveWatchWindow() {
        let model = AppModel()
        let contentView = ContentView()
            .environmentObject(model)
            .companionWindowFrame()
        let window = NSWindow(contentViewController: NSHostingController(rootView: contentView))
        window.title = "Kakitangan Companion"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(CompanionWindowLayout.preferredContentSize(on: NSScreen.main))
        window.contentMinSize = CompanionWindowLayout.minimumSize
        window.isReleasedWhenClosed = false
        window.center()

        leaveWatchModel = model
        leaveWatchWindow = window
        window.orderFrontRegardless()
        window.makeKey()
    }
}
