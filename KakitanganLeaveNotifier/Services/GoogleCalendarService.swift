import AppKit
import Foundation
import GoogleSignIn


enum CalendarResponseStatus: String, Codable, CaseIterable, Identifiable {
    case needsAction
    case declined
    case tentative
    case accepted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsAction:
            return "No response"
        case .declined:
            return "Declined"
        case .tentative:
            return "Maybe"
        case .accepted:
            return "Accepted"
        }
    }

    var icon: String {
        switch self {
        case .needsAction:
            return "questionmark.circle"
        case .declined:
            return "xmark.circle"
        case .tentative:
            return "clock.badge.questionmark"
        case .accepted:
            return "checkmark.circle"
        }
    }
}


struct MeetingReminderLeadTime: Codable, Equatable, Hashable, Identifiable, Comparable {
    let id: UUID
    let minutes: Int

    init(id: UUID = UUID(), minutes: Int) throws {
        guard (0...43_200).contains(minutes) else {
            throw NotifierError.invalidMeetingReminder
        }
        self.id = id
        self.minutes = minutes
    }

    static let defaultOptions: [MeetingReminderLeadTime] = [
        MeetingReminderLeadTime(uncheckedMinutes: 10),
        MeetingReminderLeadTime(uncheckedMinutes: 30),
    ]

    static func < (lhs: MeetingReminderLeadTime, rhs: MeetingReminderLeadTime) -> Bool {
        lhs.minutes < rhs.minutes
    }

    var label: String {
        switch minutes {
        case 0:
            return "At start"
        case 1:
            return "1 minute before"
        case 2..<60:
            return "\(minutes) minutes before"
        case 60:
            return "1 hour before"
        case 61..<1_440 where minutes % 60 == 0:
            return "\(minutes / 60) hours before"
        case 1_440:
            return "1 day before"
        case 1_441... where minutes % 1_440 == 0:
            return "\(minutes / 1_440) days before"
        default:
            return "\(minutes) minutes before"
        }
    }

    private init(uncheckedMinutes: Int) {
        id = UUID()
        minutes = uncheckedMinutes
    }
}


struct GoogleCalendarConfiguration: Codable, Equatable {
    var clientID: String
    var ownerEmail: String
    var meetingLookAheadDays: Int
    var reminderLeadTimes: [MeetingReminderLeadTime]
    var liveRefreshIntervalSeconds: Int

    init(
        clientID: String = GoogleCalendarConfiguration.bundleClientID,
        ownerEmail: String = "",
        meetingLookAheadDays: Int = 7,
        reminderLeadTimes: [MeetingReminderLeadTime] = MeetingReminderLeadTime.defaultOptions,
        liveRefreshIntervalSeconds: Int = 60,
    ) {
        self.clientID = clientID.isEmpty ? GoogleCalendarConfiguration.bundleClientID : clientID
        self.ownerEmail = ownerEmail
        self.meetingLookAheadDays = meetingLookAheadDays
        self.reminderLeadTimes = reminderLeadTimes.sorted()
        self.liveRefreshIntervalSeconds = liveRefreshIntervalSeconds
    }

    var isConfigured: Bool {
        Self.bundleClientID.hasSuffix(".apps.googleusercontent.com")
    }

    /// OAuth client ID provisioned by Firebase for this bundle ID (CLIENT_ID in GoogleService-Info.plist).
    /// Google Sign-In only reads GIDClientID from Info.plist, so `GoogleCalendarService.configureSignIn()`
    /// passes this value to it explicitly and the Firebase plist stays the single source of truth.
    static let bundleClientID: String = {
        guard
            let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let clientID = plist["CLIENT_ID"] as? String
        else {
            return ""
        }
        return clientID
    }()

    private enum CodingKeys: String, CodingKey {
        case clientID
        case ownerEmail
        case meetingLookAheadDays
        case reminderLeadTimes
        case liveRefreshIntervalSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            clientID: container.decodeIfPresent(String.self, forKey: .clientID) ?? Self.bundleClientID,
            ownerEmail: container.decodeIfPresent(String.self, forKey: .ownerEmail) ?? "",
            meetingLookAheadDays: container.decodeIfPresent(Int.self, forKey: .meetingLookAheadDays) ?? 7,
            reminderLeadTimes: container.decodeIfPresent([MeetingReminderLeadTime].self, forKey: .reminderLeadTimes) ?? MeetingReminderLeadTime.defaultOptions,
            liveRefreshIntervalSeconds: container.decodeIfPresent(Int.self, forKey: .liveRefreshIntervalSeconds) ?? 60,
        )
    }
}


struct GoogleCalendarAttendee: Codable, Equatable, Identifiable {
    let email: String
    let displayName: String?
    let isSelf: Bool
    let isOptional: Bool
    let isOrganizer: Bool
    let isResource: Bool
    let comment: String?
    let responseStatus: CalendarResponseStatus

    var id: String { email.lowercased() }

    var name: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? email : trimmed
    }
}


struct GoogleCalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let isCancelled: Bool
    let location: String?
    let meetingLink: URL?
    let organizerEmail: String?
    let attendees: [GoogleCalendarAttendee]
    let ownerEmail: String

    var attendeeEmails: [String] {
        attendees.map(\.email)
    }

    var selfResponseStatus: CalendarResponseStatus {
        attendees.first(where: \.isSelf)?.responseStatus ?? .needsAction
    }

    var timeRangeText: String {
        if isAllDay {
            return DateOnly.display(startDate)
        }
        return "\(startDate.formatted(date: .abbreviated, time: .shortened)) - \(endDate.formatted(date: .omitted, time: .shortened))"
    }

    var participantCountText: String {
        let count = attendees.count
        switch count {
        case 0:
            return "No attendees"
        case 1:
            return "1 attendee"
        default:
            return "\(count) attendees"
        }
    }
}


@MainActor
final class GoogleCalendarService {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let calendarScope = "https://www.googleapis.com/auth/calendar.events"
    private let freeBusyScope = "https://www.googleapis.com/auth/calendar.freebusy"

    static let directoryScope = "https://www.googleapis.com/auth/directory.readonly"
    static let otherContactsScope = "https://www.googleapis.com/auth/contacts.other.readonly"
    static let calendarListScope = "https://www.googleapis.com/auth/calendar.calendarlist.readonly"
    /// Optional scopes that power New Meeting autocomplete (Workspace directory, Google
    /// "Other contacts", and subscribed room calendars). Requested together on demand.
    static let suggestionScopes = [directoryScope, otherContactsScope, calendarListScope]

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Must run before any GIDSignIn call; interactive sign-in raises an exception without a configuration.
    static func configureSignIn() {
        let clientID = GoogleCalendarConfiguration.bundleClientID
        guard !clientID.isEmpty else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    var hasPreviousSignIn: Bool {
        GIDSignIn.sharedInstance.hasPreviousSignIn()
    }

    func signIn(presenting window: NSWindow?) async throws -> GIDGoogleUser {
        guard GoogleCalendarConfiguration.bundleClientID.hasSuffix(".apps.googleusercontent.com") else {
            throw NotifierError.googleCalendarNotConfigured
        }
        guard let window else {
            throw NotifierError.googleCalendarAuthenticationFailed
        }
        let result: GIDSignInResult = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GIDSignInResult, Error>) in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: window,
                hint: nil,
                additionalScopes: [calendarScope],
            ) { signInResult, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let signInResult else {
                    continuation.resume(throwing: NotifierError.googleCalendarAuthenticationFailed)
                    return
                }
                continuation.resume(returning: signInResult)
            }
        }
        return result.user
    }

    /// The signed-in user without a keychain round trip when Google Sign-In already has one.
    func currentOrRestoredUser() async throws -> GIDGoogleUser {
        if let user = GIDSignIn.sharedInstance.currentUser {
            return user
        }
        return try await restorePreviousSignIn()
    }

    func grantedScopes(of user: GIDGoogleUser) -> Set<String> {
        Set(user.grantedScopes ?? [])
    }

    func restorePreviousSignIn() async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GIDGoogleUser, Error>) in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let user else {
                    continuation.resume(throwing: NotifierError.secretNotConfigured)
                    return
                }
                continuation.resume(returning: user)
            }
        }
    }

    func accessToken(for user: GIDGoogleUser) async throws -> String {
        let refreshedUser: GIDGoogleUser = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GIDGoogleUser, Error>) in
            user.refreshTokensIfNeeded { refreshedUser, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let refreshedUser else {
                    continuation.resume(throwing: NotifierError.googleCalendarAuthenticationFailed)
                    return
                }
                continuation.resume(returning: refreshedUser)
            }
        }
        return refreshedUser.accessToken.tokenString
    }

    func userWithCalendarEventsScope(_ user: GIDGoogleUser, presenting window: NSWindow?) async throws -> GIDGoogleUser {
        try await scopedUser(user, granting: [calendarScope], presenting: window)
    }

    /// Free/busy is not covered by `calendar.events`, so it is requested incrementally the first
    /// time guest availability is checked.
    func userWithFreeBusyScope(_ user: GIDGoogleUser, presenting window: NSWindow?) async throws -> GIDGoogleUser {
        try await scopedUser(user, granting: [freeBusyScope], presenting: window)
    }

    /// Google's granular consent lets people untick individual scopes, so callers should re-read
    /// `grantedScopes(of:)` on the returned user instead of assuming all were granted.
    func userWithSuggestionScopes(_ user: GIDGoogleUser, presenting window: NSWindow?) async throws -> GIDGoogleUser {
        try await scopedUser(user, granting: Self.suggestionScopes, presenting: window)
    }

    private func scopedUser(_ user: GIDGoogleUser, granting scopes: [String], presenting window: NSWindow?) async throws -> GIDGoogleUser {
        let granted = grantedScopes(of: user)
        let missingScopes = scopes.filter { !granted.contains($0) }
        if missingScopes.isEmpty {
            return user
        }
        guard let window else {
            throw NotifierError.googleCalendarAuthenticationFailed
        }
        let result: GIDSignInResult = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GIDSignInResult, Error>) in
            user.addScopes(missingScopes, presenting: window) { signInResult, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let signInResult else {
                    continuation.resume(throwing: NotifierError.googleCalendarAuthenticationFailed)
                    return
                }
                continuation.resume(returning: signInResult)
            }
        }
        return result.user
    }

    func ownerEmail(for user: GIDGoogleUser) -> String {
        user.profile?.email ?? user.userID ?? "Google account"
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    func disconnect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            GIDSignIn.sharedInstance.disconnect { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func fetchEvents(accessToken: String, ownerEmail: String, daysAhead: Int, calendar: Calendar = .current) async throws -> [GoogleCalendarEvent] {
        let now = Date()
        let cappedDaysAhead = min(max(daysAhead, 0), 365)
        guard let endDate = calendar.date(byAdding: .day, value: cappedDaysAhead, to: now) else {
            throw NotifierError.googleCalendarRequestFailed
        }
        return try await fetchEvents(
            accessToken: accessToken,
            ownerEmail: ownerEmail,
            during: DateInterval(start: now, end: endDate),
            showDeleted: true,
            maxPages: 1,
        )
    }

    /// Recent past meetings, used to suggest guests, rooms, and locations you've used before.
    func fetchEventHistory(accessToken: String, ownerEmail: String, daysBack: Int, calendar: Calendar = .current) async throws -> [GoogleCalendarEvent] {
        let now = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -min(max(daysBack, 0), 365), to: now) else {
            throw NotifierError.googleCalendarRequestFailed
        }
        return try await fetchEvents(
            accessToken: accessToken,
            ownerEmail: ownerEmail,
            during: DateInterval(start: startDate, end: now),
            showDeleted: false,
            maxPages: 4,
        )
    }

    private func fetchEvents(
        accessToken: String,
        ownerEmail: String,
        during interval: DateInterval,
        showDeleted: Bool,
        maxPages: Int,
    ) async throws -> [GoogleCalendarEvent] {
        var events: [GoogleCalendarEvent] = []
        var pageToken: String?
        for _ in 0..<max(maxPages, 1) {
            var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")
            components?.queryItems = [
                URLQueryItem(name: "timeMin", value: Self.rfc3339Formatter.string(from: interval.start)),
                URLQueryItem(name: "timeMax", value: Self.rfc3339Formatter.string(from: interval.end)),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "showDeleted", value: showDeleted ? "true" : "false"),
                URLQueryItem(name: "maxResults", value: "250"),
            ] + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
            guard let url = components?.url else {
                throw NotifierError.googleCalendarRequestFailed
            }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let response: GoogleCalendarEventsResponse = try await decodedResponse(for: request, failure: .googleCalendarRequestFailed)
            events += response.items.compactMap { $0.event(ownerEmail: ownerEmail) }
            guard let next = response.nextPageToken else {
                break
            }
            pageToken = next
        }
        return events
    }

    /// Room (resource) calendars the user has added in Google Calendar. Non-admins can't list the
    /// organisation's rooms, so this is the closest available equivalent.
    func fetchSubscribedRooms(accessToken: String) async throws -> [MeetingRoom] {
        var rooms: [MeetingRoom] = []
        var pageToken: String?
        for _ in 0..<5 {
            var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")
            components?.queryItems = [
                URLQueryItem(name: "minAccessRole", value: "freeBusyReader"),
                URLQueryItem(name: "showHidden", value: "true"),
                URLQueryItem(name: "maxResults", value: "250"),
            ] + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
            guard let url = components?.url else {
                throw NotifierError.googleCalendarRequestFailed
            }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let response: GoogleCalendarListResponse = try await decodedResponse(for: request, failure: .googleCalendarRequestFailed)
            rooms += response.items.compactMap(\.room)
            guard let next = response.nextPageToken else {
                break
            }
            pageToken = next
        }
        return rooms
    }

    func updateResponse(
        event: GoogleCalendarEvent,
        responseStatus: CalendarResponseStatus,
        accessToken: String,
    ) async throws -> GoogleCalendarEvent {
        let attendeeEmail = event.attendees.first(where: \.isSelf)?.email ?? event.ownerEmail
        // PATCH replaces the whole attendees array, so every writable field must be echoed back or
        // Google drops other guests' names, optional flags, and RSVP notes.
        var attendeePatches = event.attendees.map { attendee in
            GoogleCalendarAttendeePatch(
                attendee: attendee,
                responseStatus: attendee.email.caseInsensitiveCompare(attendeeEmail) == .orderedSame
                    ? responseStatus
                    : attendee.responseStatus,
            )
        }
        if attendeePatches.isEmpty {
            attendeePatches = [GoogleCalendarAttendeePatch(email: attendeeEmail, responseStatus: responseStatus.rawValue)]
        }
        let patch = GoogleCalendarEventPatch(attendees: attendeePatches)
        guard let encodedEventID = event.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(encodedEventID)") else {
            throw NotifierError.googleCalendarRequestFailed
        }
        components.queryItems = [URLQueryItem(name: "sendUpdates", value: "none")]
        guard let url = components.url else {
            throw NotifierError.googleCalendarRequestFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(patch)
        let response: GoogleCalendarEventResponse = try await decodedResponse(for: request, failure: .googleCalendarRequestFailed)
        guard let updated = response.event(ownerEmail: event.ownerEmail) else {
            throw NotifierError.googleCalendarResponseDecodingFailed("Updated event did not include usable dates.")
        }
        return updated
    }

    /// Inserts a meeting on the primary calendar. Recurring meetings come back as the series'
    /// master event, so callers should refresh the expanded list afterwards.
    func createEvent(_ draft: MeetingDraft, ownerEmail: String, accessToken: String) async throws -> GoogleCalendarEvent {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")
        components?.queryItems = [
            // Required for Google to honour `conferenceData.createRequest`.
            URLQueryItem(name: "conferenceDataVersion", value: "1"),
            URLQueryItem(name: "sendUpdates", value: draft.sendsInvitations && draft.canSendInvitations ? "all" : "none"),
        ]
        guard let url = components?.url else {
            throw NotifierError.googleCalendarRequestFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(GoogleCalendarEventInsert(draft: draft))
        let response: GoogleCalendarEventResponse = try await decodedResponse(for: request, failure: .googleCalendarRequestFailed)
        guard let created = response.event(ownerEmail: ownerEmail) else {
            throw NotifierError.googleCalendarResponseDecodingFailed("Created event did not include usable dates.")
        }
        return created
    }

    /// Looks up busy blocks for each guest during `interval`. Guests whose calendars are private or
    /// outside the organisation come back as `.unknown` rather than failing the whole lookup.
    func fetchAvailability(emails: [String], during interval: DateInterval, accessToken: String) async throws -> [String: GuestAvailability] {
        guard !emails.isEmpty else {
            return [:]
        }
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/freeBusy") else {
            throw NotifierError.googleCalendarRequestFailed
        }
        var availability: [String: GuestAvailability] = [:]
        // The API accepts at most 50 calendars per query.
        for batch in stride(from: 0, to: emails.count, by: 50).map({ Array(emails[$0..<min($0 + 50, emails.count)]) }) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try encoder.encode(GoogleFreeBusyRequest(
                timeMin: Self.rfc3339Formatter.string(from: interval.start),
                timeMax: Self.rfc3339Formatter.string(from: interval.end),
                items: batch.map { GoogleFreeBusyRequest.Item(id: $0) },
            ))
            let response: GoogleFreeBusyResponse = try await decodedResponse(for: request, failure: .googleCalendarRequestFailed)
            for email in batch {
                let calendar = response.calendars.first { $0.key.caseInsensitiveCompare(email) == .orderedSame }?.value
                availability[email.lowercased()] = calendar?.availability ?? .unknown("No availability returned")
            }
        }
        return availability
    }

    private func decodedResponse<Response: Decodable>(for request: URLRequest, failure: NotifierError) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw failure
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw calendarAPIError(from: data, statusCode: httpResponse.statusCode)
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw NotifierError.googleCalendarResponseDecodingFailed(error.localizedDescription)
        }
    }

    private func calendarAPIError(from data: Data, statusCode: Int) -> Error {
        if let response = try? decoder.decode(GoogleCalendarErrorResponse.self, from: data) {
            let detail = response.error.errors.first?.reason ?? response.error.message
            return NotifierError.googleCalendarRequestFailedDetail("HTTP \(statusCode): \(response.error.message) (\(detail))")
        }
        let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let body, !body.isEmpty {
            return NotifierError.googleCalendarRequestFailedDetail("HTTP \(statusCode): \(body)")
        }
        return NotifierError.googleCalendarRequestFailedDetail("HTTP \(statusCode)")
    }

    private static let rfc3339Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}


private struct GoogleCalendarEventsResponse: Decodable {
    let items: [GoogleCalendarEventResponse]
    let nextPageToken: String?
}


private struct GoogleCalendarListResponse: Decodable {
    let items: [Entry]
    let nextPageToken: String?

    struct Entry: Decodable {
        let id: String
        let summary: String?
        let summaryOverride: String?

        var room: MeetingRoom? {
            guard id.hasSuffix(MeetingRoom.resourceCalendarSuffix) else {
                return nil
            }
            return MeetingRoom(email: id, name: summaryOverride ?? summary ?? id)
        }
    }
}


private struct GoogleCalendarErrorResponse: Decodable {
    let error: GoogleCalendarError
}


private struct GoogleCalendarError: Decodable {
    let code: Int
    let message: String
    let errors: [GoogleCalendarErrorDetail]
}


private struct GoogleCalendarErrorDetail: Decodable {
    let reason: String
}


private struct GoogleCalendarEventPatch: Encodable {
    let attendees: [GoogleCalendarAttendeePatch]
}


private struct GoogleCalendarAttendeePatch: Encodable {
    let email: String
    let displayName: String?
    let optional: Bool?
    let comment: String?
    let responseStatus: String

    init(email: String, responseStatus: String) {
        self.email = email
        displayName = nil
        optional = nil
        comment = nil
        self.responseStatus = responseStatus
    }

    init(attendee: GoogleCalendarAttendee, responseStatus: CalendarResponseStatus) {
        email = attendee.email
        displayName = attendee.displayName
        optional = attendee.isOptional ? true : nil
        comment = attendee.comment
        self.responseStatus = responseStatus.rawValue
    }
}


private struct GoogleCalendarEventResponse: Decodable {
    let id: String
    let summary: String?
    let status: String?
    let start: GoogleCalendarEventDate?
    let end: GoogleCalendarEventDate?
    let location: String?
    let hangoutLink: String?
    let htmlLink: String?
    let organizer: GoogleCalendarPerson?
    let attendees: [GoogleCalendarPerson]?
    let originalStartTime: GoogleCalendarEventDate?

    func event(ownerEmail: String) -> GoogleCalendarEvent? {
        let isCancelled = status == "cancelled"
        let startDate = start?.resolvedDate ?? originalStartTime?.resolvedDate ?? Date()
        let endDate = end?.resolvedDate ?? startDate
        return GoogleCalendarEvent(
            id: id,
            title: summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? summary! : "Untitled meeting",
            startDate: startDate,
            endDate: endDate,
            isAllDay: start?.date != nil,
            isCancelled: isCancelled,
            location: location,
            meetingLink: URL(string: hangoutLink ?? htmlLink ?? ""),
            organizerEmail: organizer?.email,
            attendees: attendees?.compactMap { $0.attendee } ?? [],
            ownerEmail: ownerEmail,
        )
    }
}


private struct GoogleCalendarEventDate: Decodable {
    let date: String?
    let dateTime: String?

    var resolvedDate: Date? {
        if let dateTime {
            return GoogleCalendarEventDate.rfc3339Formatter.date(from: dateTime)
        }
        if let date {
            return DateOnly.date(from: date)
        }
        return nil
    }

    private static let rfc3339Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}


private struct GoogleCalendarPerson: Decodable {
    let email: String?
    let displayName: String?
    let selfAttendee: Bool?
    let optional: Bool?
    let organizer: Bool?
    let resource: Bool?
    let comment: String?
    let responseStatus: String?

    enum CodingKeys: String, CodingKey {
        case email
        case displayName
        case selfAttendee = "self"
        case optional
        case organizer
        case resource
        case comment
        case responseStatus
    }

    var attendee: GoogleCalendarAttendee? {
        guard let email else { return nil }
        return GoogleCalendarAttendee(
            email: email,
            displayName: displayName,
            isSelf: selfAttendee == true,
            isOptional: optional == true,
            isOrganizer: organizer == true,
            isResource: resource == true,
            comment: comment,
            responseStatus: CalendarResponseStatus(rawValue: responseStatus ?? "") ?? .needsAction,
        )
    }
}


private struct GoogleCalendarEventInsert: Encodable {
    let summary: String
    let description: String?
    let location: String?
    let start: EventTime
    let end: EventTime
    let attendees: [Attendee]?
    let recurrence: [String]?
    let conferenceData: ConferenceData?

    struct EventTime: Encodable {
        let date: String?
        let dateTime: String?
        /// Google requires an IANA time zone on recurring events so the series follows local DST.
        let timeZone: String
    }

    struct Attendee: Encodable {
        let email: String
        /// Marks a room so Google books it rather than emailing it as a guest.
        let resource: Bool?
    }

    struct ConferenceData: Encodable {
        let createRequest: CreateRequest
    }

    struct CreateRequest: Encodable {
        let requestId: String
        let conferenceSolutionKey: SolutionKey
    }

    struct SolutionKey: Encodable {
        let type: String
    }

    init(draft: MeetingDraft, calendar: Calendar = .current) {
        let timeZone = draft.timeZone.identifier
        summary = draft.trimmedTitle.isEmpty ? "Untitled meeting" : draft.trimmedTitle
        description = Self.nonEmpty(draft.notes)
        location = Self.nonEmpty(draft.location)
        if draft.isAllDay {
            // All-day end dates are exclusive in Google Calendar, so book through the chosen last day.
            let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: draft.endDate)) ?? draft.endDate
            start = EventTime(date: DateOnly.string(from: draft.startDate), dateTime: nil, timeZone: timeZone)
            end = EventTime(date: DateOnly.string(from: exclusiveEnd), dateTime: nil, timeZone: timeZone)
        } else {
            start = EventTime(date: nil, dateTime: Self.rfc3339Formatter.string(from: draft.startDate), timeZone: timeZone)
            end = EventTime(date: nil, dateTime: Self.rfc3339Formatter.string(from: draft.endDate), timeZone: timeZone)
        }
        let allAttendees = draft.guestEmails.map { Attendee(email: $0, resource: nil) }
            + draft.rooms.map { Attendee(email: $0.email, resource: true) }
        attendees = allAttendees.isEmpty ? nil : allAttendees
        recurrence = draft.recurrence.rule(isAllDay: draft.isAllDay, calendar: calendar).map { [$0] }
        conferenceData = draft.addsGoogleMeet
            ? ConferenceData(createRequest: CreateRequest(
                requestId: UUID().uuidString,
                conferenceSolutionKey: SolutionKey(type: "hangoutsMeet"),
            ))
            : nil
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let rfc3339Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}


private struct GoogleFreeBusyRequest: Encodable {
    let timeMin: String
    let timeMax: String
    let items: [Item]

    struct Item: Encodable {
        let id: String
    }
}


private struct GoogleFreeBusyResponse: Decodable {
    let calendars: [String: CalendarAvailability]

    struct CalendarAvailability: Decodable {
        let busy: [Period]?
        let errors: [GoogleCalendarErrorDetail]?

        var availability: GuestAvailability {
            if let reason = errors?.first?.reason {
                return .unknown(reason == "notFound" ? "Calendar not shared" : reason)
            }
            let periods = (busy ?? []).compactMap(\.interval)
            return periods.isEmpty ? .free : .busy(periods)
        }
    }

    struct Period: Decodable {
        let start: String
        let end: String

        var interval: DateInterval? {
            guard let startDate = Period.formatter.date(from: start),
                  let endDate = Period.formatter.date(from: end),
                  endDate >= startDate else {
                return nil
            }
            return DateInterval(start: startDate, end: endDate)
        }

        private static let formatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter
        }()
    }
}


extension NSApplication {
    /// Window that Google's OAuth consent is anchored to.
    var oauthPresentationWindow: NSWindow? {
        keyWindow ?? windows.first { $0.isVisible }
    }
}
