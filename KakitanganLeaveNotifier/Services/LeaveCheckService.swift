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
        let leaves = try await leaves(for: configuration.accounts, passwords: [configuration.accounts[0].accountEmail: password], today: today, endDate: endDate)
        let mergedLeaves = LeaveSummary.mergingContinuous(leaves, calendar: calendar)
        return LeaveReport(
            leaves: mergedLeaves,
            daysAhead: configuration.daysAhead,
            today: today,
            checkedAccountCount: configuration.accounts.count,
        )
    }

    func check(passwords: [String: String]) async throws -> LeaveReport {
        let today = calendar.startOfDay(for: Date())
        guard let endDate = calendar.date(byAdding: .day, value: configuration.daysAhead, to: today) else {
            throw NotifierError.leaveRequestFailed
        }
        let leaves = try await leaves(for: configuration.accounts, passwords: passwords, today: today, endDate: endDate)
        let mergedLeaves = LeaveSummary.mergingContinuous(leaves, calendar: calendar)
        return LeaveReport(
            leaves: mergedLeaves,
            daysAhead: configuration.daysAhead,
            today: today,
            checkedAccountCount: configuration.accounts.count,
        )
    }

    private func leaves(
        for accounts: [NotifierAccountConfiguration],
        passwords: [String: String],
        today: Date,
        endDate: Date,
    ) async throws -> [LeaveSummary] {
        var summaries: [LeaveSummary] = []
        for account in accounts {
            guard let password = passwords[account.accountEmail] else {
                throw NotifierError.passwordNotConfigured
            }
            let token = try await apiClient.login(accountEmail: account.accountEmail, password: password)
            let records = try await apiClient.fetchLeaves(token: token, fromDate: today, toDate: endDate)
            let monitoredEmails = Set(account.monitoredEmails)
            summaries.append(contentsOf: records.compactMap { record -> LeaveSummary? in
                guard record.status.lowercased() == "approved",
                      let applicant = record.applicant,
                      monitoredEmails.contains(applicant.email.lowercased()),
                      let startDate = DateOnly.date(from: record.startDate),
                      let endDate = DateOnly.date(from: record.endDate),
                      startDate <= endDate,
                      endDate >= today else {
                    return nil
                }
                return LeaveSummary(
                    accountEmail: account.accountEmail,
                    name: applicant.preferredName ?? applicant.officialFullName ?? applicant.email,
                    email: applicant.email.lowercased(),
                    startDate: startDate,
                    endDate: endDate,
                    leaveType: record.leaveType?.name ?? "Leave",
                    period: record.period,
                )
            })
        }
        return summaries
    }
}


enum BackgroundCheckRunner {
    static func run() async {
        let configuration = ConfigurationStore().load()
        do {
            let keychainStore = KeychainStore()
            let passwords = try Dictionary(uniqueKeysWithValues: configuration.accounts.map { account in
                (account.accountEmail, try keychainStore.password(account: account.accountEmail))
            })
            let report = try await LeaveCheckService(
                configuration: configuration,
                password: passwords[configuration.accounts[0].accountEmail] ?? "",
            ).check(passwords: passwords)
            try await NotificationService.shared.send(report: report)
        } catch {
            try? await NotificationService.shared.sendFailure()
        }
    }
}
