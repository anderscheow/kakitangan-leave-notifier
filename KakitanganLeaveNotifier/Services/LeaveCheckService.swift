import Foundation


struct LeaveCheckService {
    private let configuration: NotifierConfiguration
    private let password: String
    private let apiClient: KakitanganAPIClient
    private let calendar: Calendar

    init(
        configuration: NotifierConfiguration,
        password: String,
        apiClient: KakitanganAPIClient = KakitanganAPIClient(),
        calendar: Calendar = .current,
    ) {
        self.configuration = configuration
        self.password = password
        self.apiClient = apiClient
        self.calendar = calendar
    }

    func check() async throws -> LeaveReport {
        let today = calendar.startOfDay(for: Date())
        guard let endDate = calendar.date(byAdding: .day, value: configuration.daysAhead, to: today) else {
            throw NotifierError.leaveRequestFailed
        }
        let token = try await apiClient.login(accountEmail: configuration.accountEmail, password: password)
        let records = try await apiClient.fetchLeaves(token: token, fromDate: today, toDate: endDate)
        let monitoredEmails = Set(configuration.monitoredEmails)
        let leaves = records.compactMap { record -> LeaveSummary? in
            guard record.status.lowercased() == "approved",
                  let applicant = record.applicant,
                  monitoredEmails.contains(applicant.email.lowercased()),
                  let startDate = DateOnly.date(from: record.startDate),
                  let endDate = DateOnly.date(from: record.endDate),
                  startDate >= today,
                  startDate <= endDate else {
                return nil
            }
            return LeaveSummary(
                name: applicant.preferredName ?? applicant.officialFullName ?? applicant.email,
                email: applicant.email.lowercased(),
                startDate: startDate,
                endDate: endDate,
                leaveType: record.leaveType?.name ?? "Leave",
            )
        }
        return LeaveReport(leaves: leaves.sorted { $0.startDate < $1.startDate }, daysAhead: configuration.daysAhead, today: today)
    }
}


enum BackgroundCheckRunner {
    static func run() async {
        let configuration = ConfigurationStore().load()
        do {
            let password = try KeychainStore().password(account: configuration.accountEmail)
            let report = try await LeaveCheckService(configuration: configuration, password: password).check()
            try await NotificationService.shared.send(report: report)
        } catch {
            try? await NotificationService.shared.sendFailure()
        }
    }
}
