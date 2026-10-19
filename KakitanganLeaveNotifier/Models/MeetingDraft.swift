import Foundation


/// How often a new meeting repeats. Mirrors the presets in Google Calendar's own event editor.
enum MeetingRecurrenceFrequency: String, CaseIterable, Identifiable {
    case none
    case daily
    case weekdays
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "Does not repeat"
        case .daily:
            return "Daily"
        case .weekdays:
            return "Every weekday (Mon–Fri)"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        }
    }
}


enum MeetingRecurrenceEnd: String, CaseIterable, Identifiable {
    case never
    case onDate
    case afterOccurrences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never:
            return "Never"
        case .onDate:
            return "On date"
        case .afterOccurrences:
            return "After"
        }
    }
}


struct MeetingRecurrence: Equatable {
    static let occurrenceRange = 1...730

    var frequency: MeetingRecurrenceFrequency = .none
    var end: MeetingRecurrenceEnd = .never
    var endDate: Date
    var occurrenceCount: Int = 10

    var repeats: Bool {
        frequency != .none
    }

    /// RFC 5545 rule for Google's `recurrence` field. Weekly and monthly rules repeat on the start
    /// date's weekday / day of month, which Google infers from the event start.
    func rule(isAllDay: Bool, calendar: Calendar = .current) -> String? {
        let base: String
        switch frequency {
        case .none:
            return nil
        case .daily:
            base = "FREQ=DAILY"
        case .weekdays:
            base = "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
        case .weekly:
            base = "FREQ=WEEKLY"
        case .monthly:
            base = "FREQ=MONTHLY"
        }

        switch end {
        case .never:
            return "RRULE:\(base)"
        case .afterOccurrences:
            let count = min(max(occurrenceCount, Self.occurrenceRange.lowerBound), Self.occurrenceRange.upperBound)
            return "RRULE:\(base);COUNT=\(count)"
        case .onDate:
            return "RRULE:\(base);UNTIL=\(untilValue(isAllDay: isAllDay, calendar: calendar))"
        }
    }

    /// UNTIL must match the start's value type: a plain date for all-day events, otherwise a UTC
    /// timestamp. Timed series use the last second of the chosen local day so that day is included.
    private func untilValue(isAllDay: Bool, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        if isAllDay {
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyyMMdd"
            return formatter.string(from: endDate)
        }
        let startOfDay = calendar.startOfDay(for: endDate)
        let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) ?? endDate
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: endOfDay)
    }
}


/// Everything the New Meeting sheet collects before it is sent to Google Calendar.
struct MeetingDraft: Equatable {
    var title = ""
    var startDate: Date
    var endDate: Date
    var isAllDay = false
    var guestEmails: [String] = []
    var rooms: [MeetingRoom] = []
    var location = ""
    var notes = ""
    var addsGoogleMeet = true
    var sendsInvitations = true
    var recurrence: MeetingRecurrence
    var timeZone: TimeZone = .current

    /// Defaults to the next half hour for 30 minutes, matching Google Calendar's quick-create.
    init(now: Date = Date(), calendar: Calendar = .current) {
        let wholeMinute = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        let minute = calendar.component(.minute, from: wholeMinute)
        let minutesToNextSlot = minute < 30 ? 30 - minute : 60 - minute
        let start = calendar.date(byAdding: .minute, value: minutesToNextSlot, to: wholeMinute) ?? now
        startDate = start
        endDate = start.addingTimeInterval(30 * 60)
        recurrence = MeetingRecurrence(endDate: calendar.date(byAdding: .month, value: 1, to: start) ?? start)
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSendInvitations: Bool {
        !guestEmails.isEmpty
    }

    /// Moves the start while keeping the meeting length, like Google Calendar's editor.
    mutating func moveStart(to newStart: Date) {
        let length = max(endDate.timeIntervalSince(startDate), 0)
        startDate = newStart
        endDate = newStart.addingTimeInterval(length)
    }

    /// Time span used for free/busy lookups. All-day meetings cover their whole days.
    func occupiedInterval(calendar: Calendar = .current) -> DateInterval {
        guard isAllDay else {
            return DateInterval(start: startDate, end: max(endDate, startDate))
        }
        let start = calendar.startOfDay(for: startDate)
        let lastDay = calendar.startOfDay(for: max(endDate, startDate))
        let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        return DateInterval(start: start, end: end)
    }

    func validationMessage(calendar: Calendar = .current) -> String? {
        if isAllDay {
            if calendar.startOfDay(for: endDate) < calendar.startOfDay(for: startDate) {
                return "The meeting must end on or after the day it starts."
            }
        } else if endDate <= startDate {
            return "The meeting must end after it starts."
        }
        if recurrence.repeats, recurrence.end == .onDate,
           calendar.startOfDay(for: recurrence.endDate) < calendar.startOfDay(for: startDate) {
            return "The repeat end date must be on or after the first meeting."
        }
        return nil
    }

    func hasGuest(_ email: String) -> Bool {
        guestEmails.contains { $0.caseInsensitiveCompare(email) == .orderedSame }
    }

    /// Adds each address in `input` (separated by commas, semicolons, or whitespace) that is not
    /// already a guest. Returns the tokens that were not valid email addresses.
    @discardableResult
    mutating func addGuests(from input: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",;").union(.whitespacesAndNewlines)
        var rejected: [String] = []
        for token in input.components(separatedBy: separators) where !token.isEmpty {
            guard token.contains("@") else {
                rejected.append(token)
                continue
            }
            if !hasGuest(token) {
                guestEmails.append(token)
            }
        }
        return rejected
    }

    mutating func removeGuest(_ email: String) {
        guestEmails.removeAll { $0.caseInsensitiveCompare(email) == .orderedSame }
    }

    /// Books the room and, like Google Calendar, uses its name as the location.
    mutating func addRoom(_ room: MeetingRoom) {
        if !rooms.contains(room) {
            rooms.append(room)
        }
        location = room.name
    }

    mutating func removeRoom(_ room: MeetingRoom) {
        rooms.removeAll { $0 == room }
        if location == room.name {
            location = rooms.last?.name ?? ""
        }
    }

    /// Guests and rooms, for free/busy lookups.
    var availabilityEmails: [String] {
        guestEmails + rooms.map(\.email)
    }
}


/// Free/busy result for one guest over the draft meeting's time span.
enum GuestAvailability: Equatable {
    case free
    case busy([DateInterval])
    case unknown(String)
}
