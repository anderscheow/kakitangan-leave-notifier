import Foundation


struct AuthResponse: Decodable {
    let token: String
}


struct LeavePage: Decodable {
    let results: [LeaveRecord]
}


struct LeaveRecord: Decodable {
    let applicant: LeaveApplicant?
    let endDate: String
    let leaveType: LeaveType?
    let startDate: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case applicant
        case endDate = "end_date"
        case leaveType = "leave_type"
        case startDate = "start_date"
        case status
    }
}


struct LeaveApplicant: Decodable {
    let email: String
    let officialFullName: String?
    let preferredName: String?

    enum CodingKeys: String, CodingKey {
        case email
        case officialFullName = "official_full_name"
        case preferredName = "preferred_name"
    }
}


struct LeaveType: Decodable {
    let name: String
}


/// A person returned by the "all managed employees" endpoint. Only the fields the picker needs are
/// decoded — the API also returns highly sensitive PII (NRIC, bank, salary, address) that this app
/// deliberately never reads or stores.
struct ManagedEmployee: Decodable, Identifiable, Equatable {
    let email: String
    let officialFullName: String?
    let preferredName: String?
    let department: String?
    let terminationDate: String?

    var id: String { email.lowercased() }

    var displayName: String {
        for candidate in [preferredName, officialFullName] {
            if let name = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return name
            }
        }
        return email
    }

    var departmentName: String {
        let trimmed = department?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Other" : trimmed
    }

    var isTerminated: Bool {
        terminationDate != nil
    }

    enum CodingKeys: String, CodingKey {
        case email
        case officialFullName = "official_full_name"
        case preferredName = "preferred_name"
        case department
        case terminationDate = "termination_date"
    }
}


struct LeaveSummary: Equatable, Identifiable {
    let name: String
    let email: String
    let startDate: Date
    let endDate: Date
    let leaveType: String

    var id: String {
        "\(email)|\(leaveType)|\(startDate.timeIntervalSince1970)|\(endDate.timeIntervalSince1970)"
    }

    func remainingDaysLabel(from today: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: today, to: startDate).day ?? 0
        switch days {
        case ..<0:
            return "On leave"
        case 0:
            return "starts today"
        case 1:
            return "Tomorrow"
        default:
            return "\(days) days left"
        }
    }

    /// Collapses continuous leaves into a single summary. Two leaves are merged when they belong to the
    /// same person (email) and leave type, and their date ranges touch or overlap — that is, the next
    /// leave starts no later than the day after the current one ends. Same leave type is required so the
    /// merged row keeps an accurate leave-type label.
    static func mergingContinuous(_ leaves: [LeaveSummary], calendar: Calendar = .current) -> [LeaveSummary] {
        let grouped = Dictionary(grouping: leaves) { "\($0.email)|\($0.leaveType)" }
        var merged: [LeaveSummary] = []

        for group in grouped.values {
            let sorted = group.sorted { $0.startDate < $1.startDate }
            guard var current = sorted.first else {
                continue
            }
            for next in sorted.dropFirst() {
                let dayAfterCurrentEnd = calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: calendar.startOfDay(for: current.endDate),
                ) ?? current.endDate
                if calendar.startOfDay(for: next.startDate) <= dayAfterCurrentEnd {
                    current = LeaveSummary(
                        name: current.name,
                        email: current.email,
                        startDate: current.startDate,
                        endDate: max(current.endDate, next.endDate),
                        leaveType: current.leaveType,
                    )
                } else {
                    merged.append(current)
                    current = next
                }
            }
            merged.append(current)
        }

        return merged.sorted { $0.startDate < $1.startDate }
    }
}


struct LeaveReport {
    let leaves: [LeaveSummary]
    let daysAhead: Int
    let today: Date
}


enum DateOnly {
    static func date(from value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func display(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
}
