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


struct MonitoredAccount: Identifiable, Equatable {
    let id: UUID
    var accountEmail: String
    var password: String
    var monitoredEmails: [MonitoredEmail]
    var managedEmployees: [ManagedEmployee]
    var employeeLoadError: String?

    init(
        id: UUID = UUID(),
        accountEmail: String,
        password: String = "",
        monitoredEmails: [MonitoredEmail] = [],
        managedEmployees: [ManagedEmployee] = [],
        employeeLoadError: String? = nil,
    ) {
        self.id = id
        self.accountEmail = accountEmail
        self.password = password
        self.monitoredEmails = monitoredEmails
        self.managedEmployees = managedEmployees
        self.employeeLoadError = employeeLoadError
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
    @Published var accounts: [MonitoredAccount]
    @Published var selectedAccountID: UUID?
    @Published var daysAhead: Int
    @Published var notificationTimes: [NotificationTime]
    @Published var runAtLogin: Bool
    @Published var appVisibility: AppVisibility
    @Published var statusMessage: String = ""
    @Published var isChecking: Bool = false
    @Published var isRefreshing: Bool = false
    @Published private(set) var latestReport: LeaveReport?
    @Published var isLoadingEmployees: Bool = false
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
        let loadedAccounts = Self.monitoredAccounts(from: configuration.accounts)
        accounts = loadedAccounts
        selectedAccountID = configuration.selectedAccountID ?? loadedAccounts.first?.id
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
        let savedPasswordsReady = configuration.accounts.allSatisfy { KeychainStore().hasPassword(account: $0.accountEmail) }
        screen = configuration.isComplete && savedPasswordsReady
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
        accounts.reduce(0) { $0 + normalizedMonitoredEmails(for: $1).count }
    }

    var configuredAccountCount: Int {
        accounts.filter { !$0.accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var selectedAccountIndex: Int? {
        guard let selectedAccountID else {
            return accounts.indices.first
        }
        return accounts.firstIndex { $0.id == selectedAccountID } ?? accounts.indices.first
    }

    var selectedAccount: MonitoredAccount? {
        guard let selectedAccountIndex else {
            return nil
        }
        return accounts[selectedAccountIndex]
    }

    var selectedAccountEmail: String {
        selectedAccount?.accountEmail ?? ""
    }

    var selectedAccountMonitoredEmployeeCount: Int {
        selectedAccount.map { normalizedMonitoredEmails(for: $0).count } ?? 0
    }

    var normalizedMonitoredEmails: [String] {
        guard let selectedAccount else {
            return []
        }
        return normalizedMonitoredEmails(for: selectedAccount)
    }

    private func normalizedMonitoredEmails(for account: MonitoredAccount) -> [String] {
        account.monitoredEmails
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

    /// Loads the managed-employee list only if it hasn't been fetched yet. Used to populate the
    /// picker automatically when the settings screen appears without re-hitting the API each time.
    func loadManagedEmployeesIfNeeded() async {
        guard let selectedAccount, selectedAccount.managedEmployees.isEmpty, !isLoadingEmployees else {
            return
        }
        await loadManagedEmployees()
    }

    /// Logs in with the saved account and fetches the people this account manages, dropping anyone
    /// with a termination date so only active employees are offered for selection.
    func loadManagedEmployees() async {
        guard !isLoadingEmployees else {
            return
        }
        isLoadingEmployees = true
        updateSelectedAccount { $0.employeeLoadError = nil }
        defer { isLoadingEmployees = false }

        let account = selectedAccountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty else {
            updateSelectedAccount { $0.employeeLoadError = NotifierError.invalidAccountEmail.localizedDescription }
            return
        }
        do {
            let secret = selectedAccount?.password.isEmpty == false ? selectedAccount?.password ?? "" : try keychainStore.password(account: account)
            let client = KakitanganAPIClient()
            let token = try await client.login(accountEmail: account, password: secret)
            let employees = try await client.fetchManagedEmployees(token: token)
            updateSelectedAccount {
                $0.managedEmployees = employees
                    .filter { !$0.isTerminated }
                    .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            }
        } catch {
            updateSelectedAccount { $0.employeeLoadError = error.localizedDescription }
        }
    }

    /// Active managed employees grouped by department, optionally filtered by a name/email query.
    func employeesByDepartment(matching query: String) -> [(department: String, employees: [ManagedEmployee])] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let employees = selectedAccount?.managedEmployees ?? []
        let matches = needle.isEmpty ? employees : employees.filter {
            $0.displayName.lowercased().contains(needle) || $0.email.lowercased().contains(needle)
        }
        return Dictionary(grouping: matches, by: \.departmentName)
            .map { (department: $0.key, employees: $0.value) }
            .sorted { $0.department.localizedCaseInsensitiveCompare($1.department) == .orderedAscending }
    }

    func isMonitored(_ email: String) -> Bool {
        let target = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return selectedAccount?.monitoredEmails.contains { normalized($0.address) == target } ?? false
    }

    func setMonitored(_ email: String, _ isMonitored: Bool) {
        let target = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            return
        }
        if isMonitored {
            guard !self.isMonitored(target) else {
                return
            }
            updateSelectedAccount { $0.monitoredEmails.append(MonitoredEmail(address: target)) }
        } else {
            let lowered = target.lowercased()
            updateSelectedAccount { $0.monitoredEmails.removeAll { normalized($0.address) == lowered } }
        }
    }

    /// Monitored emails that don't map to a managed employee — i.e. people added manually. Keeps the
    /// picker and the manual fallback from showing the same person twice.
    var customMonitoredEmails: [String] {
        let managed = Set((selectedAccount?.managedEmployees ?? []).map { $0.email.lowercased() })
        return normalizedMonitoredEmails
            .filter { !managed.contains($0.lowercased()) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func normalized(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func selectAccount(id: UUID) {
        guard accounts.contains(where: { $0.id == id }) else {
            return
        }
        selectedAccountID = id
    }

    func addAccount() {
        let account = MonitoredAccount(accountEmail: "")
        accounts.append(account)
        selectedAccountID = account.id
        statusMessage = "New account added. Enter its login details and people to monitor."
    }

    func removeSelectedAccount() {
        guard accounts.count > 1, let selectedAccountIndex else {
            statusMessage = "Keep at least one Kakitangan account."
            return
        }
        accounts.remove(at: selectedAccountIndex)
        selectedAccountID = accounts[min(selectedAccountIndex, accounts.count - 1)].id
        statusMessage = "Account removed."
    }

    func updateSelectedAccountEmail(_ email: String) {
        updateSelectedAccount {
            $0.accountEmail = email
            $0.managedEmployees = []
            $0.employeeLoadError = nil
        }
    }

    func updateSelectedPassword(_ password: String) {
        updateSelectedAccount { $0.password = password }
    }

    private func updateSelectedAccount(_ update: (inout MonitoredAccount) -> Void) {
        guard let selectedAccountIndex else {
            return
        }
        update(&accounts[selectedAccountIndex])
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
            let passwords = try passwords(for: configuration.accounts)
            latestReport = try await LeaveCheckService(
                configuration: configuration,
                password: passwords[configuration.accounts[0].accountEmail] ?? "",
            ).check(passwords: passwords)
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
            let passwords = try passwords(for: configuration.accounts)
            let report = try await LeaveCheckService(
                configuration: configuration,
                password: passwords[configuration.accounts[0].accountEmail] ?? "",
            ).check(passwords: passwords)
            latestReport = report
            statusMessage = "Checked successfully: \(report.leaves.count) matching leave record(s)."
            // Deliver off the UI critical path: the 1s throttle between multiple alerts must not
            // hold the spinner or defer the status message. The background runner still awaits.
            Task { try? await NotificationService.shared.send(report: report) }
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
        addresses.map { MonitoredEmail(address: $0) }
    }

    private static func monitoredAccounts(from accounts: [NotifierAccountConfiguration]) -> [MonitoredAccount] {
        accounts.map {
            MonitoredAccount(
                id: $0.id,
                accountEmail: $0.accountEmail,
                monitoredEmails: monitoredEmails(from: $0.monitoredEmails),
            )
        }
    }

    private func makeConfiguration() throws -> NotifierConfiguration {
        let accountConfigurations = try accounts.map { account in
            try NotifierAccountConfiguration(
                id: account.id,
                accountEmail: account.accountEmail,
                monitoredEmails: normalizedMonitoredEmails(for: account).map { $0.lowercased() },
            )
        }
        return try NotifierConfiguration(
            accounts: accountConfigurations,
            selectedAccountID: selectedAccountID,
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
        if requiresPassword {
            for account in accounts {
                let normalizedEmail = account.accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if account.password.isEmpty && !keychainStore.hasPassword(account: normalizedEmail) {
                    throw NotifierError.passwordNotConfigured
                }
            }
        }
        for account in accounts where !account.password.isEmpty {
            let normalizedEmail = account.accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            try keychainStore.save(password: account.password, account: normalizedEmail)
        }
        accounts = accounts.map {
            MonitoredAccount(
                id: $0.id,
                accountEmail: $0.accountEmail,
                monitoredEmails: $0.monitoredEmails,
                managedEmployees: $0.managedEmployees,
                employeeLoadError: $0.employeeLoadError,
            )
        }
        try configurationStore.save(configuration)
        return configuration
    }

    private func loadSavedConfiguration() {
        let configuration = configurationStore.load()
        accounts = Self.monitoredAccounts(from: configuration.accounts)
        selectedAccountID = configuration.selectedAccountID ?? accounts.first?.id
        daysAhead = configuration.daysAhead
        notificationTimes = configuration.notificationTimes
        runAtLogin = configuration.runAtLogin
        appVisibility = configuration.appVisibility
        _ = applyAppVisibility()
    }

    private func passwords(for accounts: [NotifierAccountConfiguration]) throws -> [String: String] {
        try Dictionary(uniqueKeysWithValues: accounts.map { account in
            (account.accountEmail, try keychainStore.password(account: account.accountEmail))
        })
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
