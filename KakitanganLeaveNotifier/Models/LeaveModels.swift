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
        case 0:
            return "starts today"
        case 1:
            return "1 day left"
        default:
            return "\(days) days left"
        }
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
