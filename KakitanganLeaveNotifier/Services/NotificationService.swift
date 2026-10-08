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
                title: "Kakitangan Leave Watch",
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

    func sendFailure() async throws {
        guard #available(macOS 12.0, *) else {
            return
        }
        try await ensureAuthorizedForDelivery()
        try await add(
            title: "Kakitangan Leave Watch",
            body: "Unable to check leave. Open the app to review its configuration.",
        )
    }

    func sendTest() async throws {
        guard #available(macOS 12.0, *) else {
            throw NotifierError.unsupportedMacOS
        }
        try await ensureAuthorizedForDelivery()
        try await add(
            title: "Kakitangan Leave Watch",
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
    private func add(title: String, body: String, threadIdentifier: String? = nil) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        if let threadIdentifier {
            content.threadIdentifier = threadIdentifier
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try await center.add(request)
    }
}
