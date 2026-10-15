import Foundation
import UserNotifications


enum NotificationPermissionStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case unsupported
}


final class NotificationService {
    static let shared = NotificationService()

    /// Delay inserted between consecutive notifications so macOS delivers them
    /// one by one instead of collapsing a rapid burst.
    private let throttleIntervalNanoseconds: UInt64 = 1_000_000_000

    private let center = UNUserNotificationCenter.current()

    private init() {}

    func permissionStatus() async -> NotificationPermissionStatus {
        guard #available(macOS 12.0, *) else {
            return .unsupported
        }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        default:
            return .denied
        }
    }

    func requestPermission() async throws -> NotificationPermissionStatus {
        guard #available(macOS 12.0, *) else {
            throw NotifierError.unsupportedMacOS
        }
        let status = await permissionStatus()
        guard status == .notDetermined else {
            if status == .authorized {
                return status
            }
            throw NotifierError.notificationPermissionDenied
        }
        guard try await center.requestAuthorization(options: [.alert, .sound]) else {
            throw NotifierError.notificationPermissionDenied
        }
        return await permissionStatus()
    }

    func send(report: LeaveReport) async throws {
        guard #available(macOS 12.0, *) else {
            throw NotifierError.unsupportedMacOS
        }
        try await ensureAuthorizedForDelivery()
        if report.leaves.isEmpty {
            let accountText = report.checkedAccountCount == 1 ? "account" : "accounts"
            try await add(
                title: "Kakitangan Companion",
                body: "No configured employees across \(report.checkedAccountCount) \(accountText) start approved leave in the next \(report.daysAhead) days.",
            )
            return
        }
        for (index, leave) in report.leaves.enumerated() {
            try await add(
                title: "\(leave.name): \(leave.remainingDaysLabel(from: report.today))",
                body: "\(leave.leaveTypeWithPeriod) • \(DateOnly.display(leave.startDate))–\(DateOnly.display(leave.endDate)) • \(leave.accountEmail)",
                threadIdentifier: "\(leave.accountEmail)-\(leave.email)",
            )
            if index < report.leaves.count - 1 {
                try await Task.sleep(nanoseconds: throttleIntervalNanoseconds)
            }
        }
    }

    func scheduleMeetingReminders(events: [GoogleCalendarEvent], leadTimes: [MeetingReminderLeadTime]) async throws {
        guard #available(macOS 12.0, *) else {
            throw NotifierError.unsupportedMacOS
        }
        try await ensureAuthorizedForDelivery()
        let prefix = "meeting-reminder-"
        let pending = await center.pendingNotificationRequests()
        let pendingMeetingIDs = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pendingMeetingIDs)

        let now = Date()
        for event in events where !event.isCancelled && !event.isAllDay {
            for leadTime in leadTimes {
                let fireDate = event.startDate.addingTimeInterval(TimeInterval(-leadTime.minutes * 60))
                guard fireDate > now else { continue }
                let title = leadTime.minutes == 0 ? "Meeting now" : "Meeting in \(leadTime.label.replacingOccurrences(of: " before", with: ""))"
                try await add(
                    title: title,
                    body: "\(event.title) • \(event.startDate.formatted(date: .abbreviated, time: .shortened))",
                    threadIdentifier: event.id,
                    identifier: "\(prefix)\(event.id)-\(leadTime.minutes)",
                    triggerDate: fireDate,
                )
            }
        }
    }

    func sendCancelledMeetingAlert(event: GoogleCalendarEvent) async throws {
        guard #available(macOS 12.0, *) else {
            throw NotifierError.unsupportedMacOS
        }
        try await ensureAuthorizedForDelivery()
        try await add(
            title: "Meeting cancelled",
            body: "\(event.title) • \(event.startDate.formatted(date: .abbreviated, time: .shortened))",
            threadIdentifier: event.id,
        )
    }

    func sendFailure() async throws {
        guard #available(macOS 12.0, *) else {
            return
        }
        try await ensureAuthorizedForDelivery()
        try await add(
            title: "Kakitangan Companion",
            body: "Unable to check leave. Open the app to review its configuration.",
        )
    }

    func sendTest() async throws {
        guard #available(macOS 12.0, *) else {
            throw NotifierError.unsupportedMacOS
        }
        try await ensureAuthorizedForDelivery()
        try await add(
            title: "Kakitangan Companion",
            body: "Time Sensitive notifications are configured correctly.",
        )
    }

    @available(macOS 12.0, *)
    private func ensureAuthorizedForDelivery() async throws {
        guard await permissionStatus() == .authorized else {
            throw NotifierError.notificationPermissionDenied
        }
    }

    @available(macOS 12.0, *)
    private func add(
        title: String,
        body: String,
        threadIdentifier: String? = nil,
        identifier: String = UUID().uuidString,
        triggerDate: Date? = nil,
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        if let threadIdentifier {
            content.threadIdentifier = threadIdentifier
        }
        let trigger: UNNotificationTrigger?
        if let triggerDate {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else {
            trigger = nil
        }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
    }
}
