import Foundation


enum AppVisibility: String, Codable, CaseIterable, Identifiable {
    case menuBarAndDock
    case menuBarOnly
    case dockOnly

    var id: String {
        rawValue
    }

    var showsInMenuBar: Bool {
        self != .dockOnly
    }

    var showsInDock: Bool {
        self != .menuBarOnly
    }
}


struct NotificationTime: Codable, Equatable, Hashable, Identifiable, Comparable {
    let id: UUID
    let hour: Int
    let minute: Int

    init(id: UUID = UUID(), hour: Int, minute: Int) throws {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw NotifierError.invalidNotificationTimes
        }
        self.id = id
        self.hour = hour
        self.minute = minute
    }

    static let defaultTime = NotificationTime(uncheckedHour: 9, minute: 0)

    static func < (lhs: NotificationTime, rhs: NotificationTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    var minutesSinceMidnight: Int {
        (hour * 60) + minute
    }

    private init(uncheckedHour: Int, minute: Int) {
        id = UUID()
        hour = uncheckedHour
        self.minute = minute
    }
}


struct NotifierConfiguration: Codable, Equatable {
    let accountEmail: String
    let monitoredEmails: [String]
    let daysAhead: Int
    let notificationTimes: [NotificationTime]
    let runAtLogin: Bool
    let appVisibility: AppVisibility

    init(
        accountEmail: String,
        monitoredEmails: [String],
        daysAhead: Int,
        notificationTimes: [NotificationTime] = [.defaultTime],
        runAtLogin: Bool = true,
        appVisibility: AppVisibility = .menuBarAndDock,
    ) throws {
        let normalizedAccountEmail = accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedMonitoredEmails = Array(Set(monitoredEmails.map { $0.lowercased() })).sorted()
        let normalizedNotificationTimes = notificationTimes.sorted()
        guard normalizedAccountEmail.contains("@") else {
            throw NotifierError.invalidAccountEmail
        }
        guard !normalizedMonitoredEmails.isEmpty, normalizedMonitoredEmails.allSatisfy({ $0.contains("@") }) else {
            throw NotifierError.invalidMonitoredEmails
        }
        guard (0...365).contains(daysAhead) else {
            throw NotifierError.invalidDaysAhead
        }
        guard Set(normalizedNotificationTimes.map(\.minutesSinceMidnight)).count == normalizedNotificationTimes.count else {
            throw NotifierError.invalidNotificationTimes
        }

        self.accountEmail = normalizedAccountEmail
        self.monitoredEmails = normalizedMonitoredEmails
        self.daysAhead = daysAhead
        self.notificationTimes = normalizedNotificationTimes
        self.runAtLogin = runAtLogin
        self.appVisibility = appVisibility
    }

    static let empty = NotifierConfiguration(
        uncheckedAccountEmail: "",
        monitoredEmails: [],
        daysAhead: 7,
        notificationTimes: [.defaultTime],
        runAtLogin: true,
        appVisibility: .menuBarAndDock,
    )

    private init(
        uncheckedAccountEmail: String,
        monitoredEmails: [String],
        daysAhead: Int,
        notificationTimes: [NotificationTime],
        runAtLogin: Bool,
        appVisibility: AppVisibility,
    ) {
        accountEmail = uncheckedAccountEmail
        self.monitoredEmails = monitoredEmails
        self.daysAhead = daysAhead
        self.notificationTimes = notificationTimes
        self.runAtLogin = runAtLogin
        self.appVisibility = appVisibility
    }

    var isComplete: Bool {
        accountEmail.contains("@")
            && !monitoredEmails.isEmpty
            && monitoredEmails.allSatisfy { $0.contains("@") }
            && (0...365).contains(daysAhead)
    }

    var hasAutomatedCheck: Bool {
        !notificationTimes.isEmpty || runAtLogin
    }

    private enum CodingKeys: String, CodingKey {
        case accountEmail
        case monitoredEmails
        case daysAhead
        case notificationTimes
        case runAtLogin
        case appVisibility
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            accountEmail: container.decode(String.self, forKey: .accountEmail),
            monitoredEmails: container.decode([String].self, forKey: .monitoredEmails),
            daysAhead: container.decode(Int.self, forKey: .daysAhead),
            notificationTimes: container.decodeIfPresent([NotificationTime].self, forKey: .notificationTimes) ?? [.defaultTime],
            runAtLogin: container.decodeIfPresent(Bool.self, forKey: .runAtLogin) ?? true,
            appVisibility: container.decodeIfPresent(AppVisibility.self, forKey: .appVisibility) ?? .menuBarAndDock,
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accountEmail, forKey: .accountEmail)
        try container.encode(monitoredEmails, forKey: .monitoredEmails)
        try container.encode(daysAhead, forKey: .daysAhead)
        try container.encode(notificationTimes, forKey: .notificationTimes)
        try container.encode(runAtLogin, forKey: .runAtLogin)
        try container.encode(appVisibility, forKey: .appVisibility)
    }
}


final class ConfigurationStore {
    private let key = "notifierConfiguration"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> NotifierConfiguration {
        guard let data = defaults.data(forKey: key) else {
            return .empty
        }
        return (try? JSONDecoder().decode(NotifierConfiguration.self, from: data)) ?? .empty
    }

    func save(_ configuration: NotifierConfiguration) throws {
        defaults.set(try JSONEncoder().encode(configuration), forKey: key)
    }
}


enum NotifierError: LocalizedError {
    case invalidAccountEmail
    case invalidMonitoredEmails
    case invalidDaysAhead
    case invalidNotificationTimes
    case notificationTimesRequired
    case automatedCheckNotConfigured
    case passwordNotConfigured
    case authenticationFailed
    case leaveRequestFailed
    case notificationPermissionDenied
    case unsupportedMacOS
    case launchAgentFailed

    var errorDescription: String? {
        switch self {
        case .invalidAccountEmail:
            return "Enter a valid Kakitangan login email."
        case .invalidMonitoredEmails:
            return "Enter at least one valid employee email to monitor."
        case .invalidDaysAhead:
            return "The look-ahead window must be between 0 and 365 days."
        case .invalidNotificationTimes:
            return "Notification times must be valid and cannot be duplicated."
        case .notificationTimesRequired:
            return "Add at least one weekday notification time before enabling the schedule."
        case .automatedCheckNotConfigured:
            return "Add a weekday time or enable Check at sign-in before enabling automatic checks."
        case .passwordNotConfigured:
            return "Enter and save the Kakitangan password first."
        case .authenticationFailed:
            return "Kakitangan authentication failed. Check the saved account and password."
        case .leaveRequestFailed:
            return "Kakitangan leave data could not be retrieved."
        case .notificationPermissionDenied:
            return "Allow notifications for Kakitangan Leave Notifier in System Settings."
        case .unsupportedMacOS:
            return "Time Sensitive notifications require macOS 12 or later."
        case .launchAgentFailed:
            return "The weekday launch agent could not be installed."
        }
    }
}
