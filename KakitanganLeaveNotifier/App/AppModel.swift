import AppKit
import Foundation
import ServiceManagement


enum AppScreen: Equatable {
    case setup
    case dashboard
    case editing
}


enum LoginItemStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
    case notFound
}


struct MonitoredEmail: Identifiable, Equatable {
    let id: UUID
    var address: String

    init(id: UUID = UUID(), address: String) {
        self.id = id
        self.address = address
    }
}


extension Notification.Name {
    static let appVisibilityDidChange = Notification.Name("com.kakitangan.leave-notifier.app-visibility-did-change")
    static let openSettingsRequested = Notification.Name("com.kakitangan.leave-notifier.open-settings-requested")
}


/// Applies the Dock/menu-bar activation policy from the configured visibility, promoting to
/// `.regular` whenever a titled window is on screen so the Dock icon appears while a window shows.
@MainActor
@discardableResult
func applyEffectiveActivationPolicy(for visibility: AppVisibility) -> Bool {
    let hasVisibleWindow = NSApp.windows.contains { window in
        window.isVisible && window.styleMask.contains(.titled)
    }
    let policy: NSApplication.ActivationPolicy = visibility.showsInDock || hasVisibleWindow ? .regular : .accessory
    guard NSApp.activationPolicy() != policy else {
        return true
    }
    return NSApp.setActivationPolicy(policy)
}


@MainActor
final class AppModel: ObservableObject {
    @Published var accountEmail: String
    @Published var password: String = ""
    @Published var monitoredEmails: [MonitoredEmail]
    @Published var daysAhead: Int
    @Published var notificationTimes: [NotificationTime]
    @Published var runAtLogin: Bool
    @Published var appVisibility: AppVisibility
    @Published var statusMessage: String = ""
    @Published var isChecking: Bool = false
    @Published var isRefreshing: Bool = false
    @Published private(set) var latestReport: LeaveReport?
    @Published var isInstallingSchedule: Bool = false
    @Published var isRequestingPermission: Bool = false
    @Published private(set) var screen: AppScreen
    @Published private(set) var notificationPermission: NotificationPermissionStatus = .notDetermined
    @Published private(set) var isWeekdayScheduleInstalled: Bool
    @Published private(set) var needsScheduleRefresh: Bool
    @Published private(set) var loginItemStatus: LoginItemStatus = .unavailable

    private let configurationStore = ConfigurationStore()
    private let keychainStore = KeychainStore()
    private var openSettingsObserver: NSObjectProtocol?

    init() {
        let configuration = configurationStore.load()
        accountEmail = configuration.accountEmail
        monitoredEmails = Self.monitoredEmails(from: configuration.monitoredEmails)
        daysAhead = configuration.daysAhead
        notificationTimes = configuration.notificationTimes
        runAtLogin = configuration.runAtLogin
        appVisibility = configuration.appVisibility
        let scheduleInstalled = LaunchAgentService.isWeekdayScheduleInstalled
        isWeekdayScheduleInstalled = scheduleInstalled
        needsScheduleRefresh = scheduleInstalled && !LaunchAgentService.isScheduleCurrent(
            times: configuration.notificationTimes,
            runAtLogin: configuration.runAtLogin,
        )
        screen = configuration.isComplete && keychainStore.hasPassword(account: configuration.accountEmail)
            ? .dashboard
            : .setup
        _ = applyAppVisibility()
        refreshLoginItemStatus()

        openSettingsObserver = NotificationCenter.default.addObserver(
            forName: .openSettingsRequested,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.beginEditing()
            }
        }

        Task {
            await refreshNotificationPermission()
        }
    }

    deinit {
        if let openSettingsObserver {
            NotificationCenter.default.removeObserver(openSettingsObserver)
        }
    }

    var monitoredEmployeeCount: Int {
        normalizedMonitoredEmails.count
    }

    var normalizedMonitoredEmails: [String] {
        monitoredEmails
            .map { $0.address.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var isEditing: Bool {
        screen == .editing
    }

    var hasNotificationTimes: Bool {
        !notificationTimes.isEmpty
    }

    var hasAutomatedCheck: Bool {
        hasNotificationTimes || runAtLogin
    }

    var isOpenAtLoginEnabled: Bool {
        loginItemStatus == .enabled
    }

    var canConfigureOpenAtLogin: Bool {
        loginItemStatus != .unavailable
    }

    var notificationScheduleSummary: String {
        notificationTimes
            .sorted()
            .map { time in
                Self.timeFormatter.string(from: date(for: time))
            }
            .joined(separator: ", ")
    }

    func saveSetup() {
        do {
            let configuration = try persistConfiguration(requiresPassword: true)
            if isWeekdayScheduleInstalled {
                if !configuration.hasAutomatedCheck {
                    try LaunchAgentService.uninstallWeekdaySchedule()
                } else {
                    try LaunchAgentService.installWeekdaySchedule(
                        times: configuration.notificationTimes,
                        runAtLogin: configuration.runAtLogin,
                    )
                }
                isWeekdayScheduleInstalled = LaunchAgentService.isWeekdayScheduleInstalled
                needsScheduleRefresh = isWeekdayScheduleInstalled && !LaunchAgentService.isScheduleCurrent(
                    times: configuration.notificationTimes,
                    runAtLogin: configuration.runAtLogin,
                )
            }
            screen = .dashboard
            statusMessage = !configuration.hasAutomatedCheck
                ? "Settings saved. Automatic checks are disabled."
                : "Settings saved securely."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func beginEditing() {
        screen = .editing
        statusMessage = ""
    }

    func cancelEditing() {
        loadSavedConfiguration()
        screen = .dashboard
        statusMessage = "Changes discarded."
    }

    func refreshNotificationPermission() async {
        notificationPermission = await NotificationService.shared.permissionStatus()
    }

    func refreshLoginItemStatus() {
        guard #available(macOS 13.0, *) else {
            loginItemStatus = .unavailable
            return
        }

        switch SMAppService.mainApp.status {
        case .enabled:
            loginItemStatus = .enabled
        case .notRegistered:
            loginItemStatus = .disabled
        case .requiresApproval:
            loginItemStatus = .requiresApproval
        case .notFound:
            loginItemStatus = .notFound
        @unknown default:
            loginItemStatus = .notFound
        }
    }

    func setOpenAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            loginItemStatus = .unavailable
            statusMessage = "Open at Login is available on macOS 13 or later."
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginItemStatus()
            statusMessage = enabled
                ? "Kakitangan Leave Notifier was added to Open at Login."
                : "Kakitangan Leave Notifier was removed from Open at Login."
        } catch {
            refreshLoginItemStatus()
            statusMessage = "macOS could not update Open at Login: \(error.localizedDescription)"
        }
    }

    func openLoginItemSettings() {
        guard #available(macOS 13.0, *) else {
            statusMessage = "Open at Login is available on macOS 13 or later."
            return
        }
        SMAppService.openSystemSettingsLoginItems()
    }

    func setAppVisibility(_ visibility: AppVisibility) {
        let previousVisibility = appVisibility
        appVisibility = visibility
        guard applyAppVisibility() else {
            appVisibility = previousVisibility
            statusMessage = "macOS could not update the app visibility."
            return
        }
        notifyAppVisibilityChange()
    }

    func requestNotificationPermission() async {
        isRequestingPermission = true
        defer { isRequestingPermission = false }

        do {
            notificationPermission = try await NotificationService.shared.requestPermission()
            statusMessage = "Notifications are enabled. Choose Time Sensitive and Persistent alerts in System Settings."
        } catch {
            notificationPermission = await NotificationService.shared.permissionStatus()
            statusMessage = error.localizedDescription
        }
    }

    func date(for notificationTime: NotificationTime) -> Date {
        Calendar.current.date(
            bySettingHour: notificationTime.hour,
            minute: notificationTime.minute,
            second: 0,
            of: Date(),
        ) ?? Date()
    }

    func addMonitoredEmail() {
        monitoredEmails.append(MonitoredEmail(address: ""))
    }

    func removeMonitoredEmail(id: MonitoredEmail.ID) {
        monitoredEmails.removeAll { $0.id == id }
        if monitoredEmails.isEmpty {
            monitoredEmails.append(MonitoredEmail(address: ""))
        }
    }

    func addNotificationTime() {
        let usedMinutes = Set(notificationTimes.map(\.minutesSinceMidnight))
        let startingMinute = (notificationTimes.sorted().last?.minutesSinceMidnight ?? 480) + 60
        let minuteOfDay = (0..<1_440)
            .map { (startingMinute + $0) % 1_440 }
            .first { !usedMinutes.contains($0) }
        guard let minuteOfDay,
              let notificationTime = try? NotificationTime(
                  hour: minuteOfDay / 60,
                  minute: minuteOfDay % 60,
              ) else {
            statusMessage = "Another notification time could not be added."
            return
        }
        notificationTimes.append(notificationTime)
        notificationTimes.sort()
    }

    func updateNotificationTime(id: UUID, to date: Date) {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        guard let replacement = try? NotificationTime(id: id, hour: hour, minute: minute) else {
            return
        }
        guard !notificationTimes.contains(where: {
            $0.id != id && $0.minutesSinceMidnight == replacement.minutesSinceMidnight
        }) else {
            statusMessage = "Each notification time must be different."
            return
        }
        guard let index = notificationTimes.firstIndex(where: { $0.id == id }) else {
            return
        }
        notificationTimes[index] = replacement
        notificationTimes.sort()
    }

    func removeNotificationTime(id: UUID) {
        notificationTimes.removeAll { $0.id == id }
    }

    /// Read-only fetch for the dashboard listing. Loads the latest leave report without sending
    /// notifications, so opening or refreshing the dashboard never spams alerts.
    func refreshWatchList() async {
        guard !isRefreshing else {
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let configuration = try makeConfiguration()
            let password = try keychainStore.password(account: configuration.accountEmail)
            latestReport = try await LeaveCheckService(configuration: configuration, password: password).check()
            statusMessage = ""
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func checkNow() async {
        isChecking = true
        defer { isChecking = false }

        do {
            let configuration = try persistConfiguration(requiresPassword: true)
            let password = try keychainStore.password(account: configuration.accountEmail)
            let report = try await LeaveCheckService(configuration: configuration, password: password).check()
            latestReport = report
            try await NotificationService.shared.send(report: report)
            statusMessage = "Checked successfully: \(report.leaves.count) matching leave record(s)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func installWeekdaySchedule() {
        isInstallingSchedule = true
        defer { isInstallingSchedule = false }

        do {
            let configuration = try saveForBackgroundCheck()
            try LaunchAgentService.installWeekdaySchedule(
                times: configuration.notificationTimes,
                runAtLogin: configuration.runAtLogin,
            )
            isWeekdayScheduleInstalled = LaunchAgentService.isWeekdayScheduleInstalled
            needsScheduleRefresh = false
            statusMessage = "Automatic leave checks are enabled."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func testNotification() async {
        do {
            try await NotificationService.shared.sendTest()
            statusMessage = "Test notification sent."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private static func monitoredEmails(from addresses: [String]) -> [MonitoredEmail] {
        let mapped = addresses.map { MonitoredEmail(address: $0) }
        return mapped.isEmpty ? [MonitoredEmail(address: "")] : mapped
    }

    private func makeConfiguration() throws -> NotifierConfiguration {
        let emails = normalizedMonitoredEmails.map { $0.lowercased() }
        return try NotifierConfiguration(
            accountEmail: accountEmail,
            monitoredEmails: emails,
            daysAhead: daysAhead,
            notificationTimes: notificationTimes,
            runAtLogin: runAtLogin,
            appVisibility: appVisibility,
        )
    }

    private func saveForBackgroundCheck() throws -> NotifierConfiguration {
        try persistConfiguration(requiresPassword: true)
    }

    private func persistConfiguration(requiresPassword: Bool) throws -> NotifierConfiguration {
        let configuration = try makeConfiguration()
        if requiresPassword && password.isEmpty && !keychainStore.hasPassword(account: configuration.accountEmail) {
            throw NotifierError.passwordNotConfigured
        }
        if !password.isEmpty {
            try keychainStore.save(password: password, account: configuration.accountEmail)
            password = ""
        }
        try configurationStore.save(configuration)
        return configuration
    }

    private func loadSavedConfiguration() {
        let configuration = configurationStore.load()
        accountEmail = configuration.accountEmail
        monitoredEmails = Self.monitoredEmails(from: configuration.monitoredEmails)
        daysAhead = configuration.daysAhead
        notificationTimes = configuration.notificationTimes
        runAtLogin = configuration.runAtLogin
        appVisibility = configuration.appVisibility
        _ = applyAppVisibility()
        password = ""
    }

    private func applyAppVisibility() -> Bool {
        applyEffectiveActivationPolicy(for: appVisibility)
    }

    private func notifyAppVisibilityChange() {
        NotificationCenter.default.post(
            name: .appVisibilityDidChange,
            object: nil,
            userInfo: ["appVisibility": appVisibility.rawValue],
        )
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
