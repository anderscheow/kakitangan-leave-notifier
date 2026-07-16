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
            try await add(
                title: "Kakitangan Leave Watch",
                body: "No configured employees start approved leave in the next \(report.daysAhead) days.",
            )
            return
        }
        for leave in report.leaves {
            try await add(
                title: "\(leave.name): \(leave.remainingDaysLabel(from: report.today))",
                body: "\(leave.leaveType) • \(DateOnly.display(leave.startDate))–\(DateOnly.display(leave.endDate))",
                threadIdentifier: leave.email,
            )
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
