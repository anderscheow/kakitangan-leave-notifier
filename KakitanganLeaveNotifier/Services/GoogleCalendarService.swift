import CryptoKit
import Foundation
import Network
import Security


struct GoogleCalendarConfiguration: Codable, Equatable {
    var clientID: String
    var clientSecret: String
    var ownerEmail: String
    var meetingLookAheadDays: Int

    init(
        clientID: String = "",
        clientSecret: String = "",
        ownerEmail: String = "",
        meetingLookAheadDays: Int = 7,
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.ownerEmail = ownerEmail
        self.meetingLookAheadDays = meetingLookAheadDays
    }

    var isConfigured: Bool {
        clientID.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(".apps.googleusercontent.com")
    }
}


struct GoogleCalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let meetingLink: URL?
    let organizerEmail: String?
    let attendeeEmails: [String]
    let ownerEmail: String

    var timeRangeText: String {
        if isAllDay {
            return DateOnly.display(startDate)
        }
        return "\(startDate.formatted(date: .abbreviated, time: .shortened)) - \(endDate.formatted(date: .omitted, time: .shortened))"
    }

    var participantCountText: String {
        let count = attendeeEmails.count
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


struct GoogleCalendarAuthStart {
    let authorizationURL: URL
    let codeVerifier: String
    let state: String
    let redirectURI: String
    let server: GoogleOAuthLoopbackServer
}


actor GoogleCalendarService {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let calendarScope = "https://www.googleapis.com/auth/calendar.events.readonly openid email profile"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func beginAuthorization(clientID: String) throws -> GoogleCalendarAuthStart {
        let codeVerifier = Self.secureRandomString(length: 64)
        let state = Self.secureRandomString(length: 32)
        let server = try GoogleOAuthLoopbackServer()
        let redirectURI = server.redirectURI
        guard var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth") else {
            throw NotifierError.googleCalendarAuthenticationFailed
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: calendarScope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let authorizationURL = components.url else {
            throw NotifierError.googleCalendarAuthenticationFailed
        }
        return GoogleCalendarAuthStart(
            authorizationURL: authorizationURL,
            codeVerifier: codeVerifier,
            state: state,
            redirectURI: redirectURI,
            server: server,
        )
    }

    func finishAuthorization(start: GoogleCalendarAuthStart, configuration: GoogleCalendarConfiguration) async throws -> GoogleCalendarTokenSet {
        let redirect = try await start.server.waitForRedirect()
        guard redirect.state == start.state else {
            throw NotifierError.googleCalendarAuthenticationFailed
        }
        return try await exchangeCode(
            redirect.code,
            clientID: configuration.clientID,
            clientSecret: configuration.clientSecret,
            redirectURI: start.redirectURI,
            codeVerifier: start.codeVerifier,
        )
    }

    func refreshAccessToken(refreshToken: String, configuration: GoogleCalendarConfiguration) async throws -> GoogleCalendarTokenSet {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var values = [
            "client_id": configuration.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        if !configuration.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values["client_secret"] = configuration.clientSecret
        }
        request.httpBody = Self.formBody(values)
        let tokenSet: GoogleCalendarTokenSet = try await decodedResponse(for: request, failure: .googleCalendarAuthenticationFailed)
        return tokenSet
    }

    func fetchOwnerEmail(accessToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let profile: GoogleUserInfoResponse = try await decodedResponse(for: request, failure: .googleCalendarRequestFailed)
        return profile.email
    }

    func fetchEvents(accessToken: String, ownerEmail: String, daysAhead: Int, calendar: Calendar = .current) async throws -> [GoogleCalendarEvent] {
        let now = Date()
        let cappedDaysAhead = min(max(daysAhead, 0), 365)
        guard let endDate = calendar.date(byAdding: .day, value: cappedDaysAhead, to: now) else {
            throw NotifierError.googleCalendarRequestFailed
        }
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")
        components?.queryItems = [
            URLQueryItem(name: "timeMin", value: Self.rfc3339Formatter.string(from: now)),
            URLQueryItem(name: "timeMax", value: Self.rfc3339Formatter.string(from: endDate)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "40"),
            URLQueryItem(name: "eventTypes", value: "default"),
        ]
        guard let url = components?.url else {
            throw NotifierError.googleCalendarRequestFailed
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: GoogleCalendarEventsResponse = try await decodedResponse(for: request, failure: .googleCalendarRequestFailed)
        return response.items.compactMap { $0.event(ownerEmail: ownerEmail) }
    }

    private func exchangeCode(
        _ code: String,
        clientID: String,
        clientSecret: String,
        redirectURI: String,
        codeVerifier: String,
    ) async throws -> GoogleCalendarTokenSet {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var values = [
            "client_id": clientID,
            "code": code,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier,
        ]
        if !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values["client_secret"] = clientSecret
        }
        request.httpBody = Self.formBody(values)
        return try await decodedResponse(for: request, failure: .googleCalendarAuthenticationFailed)
    }

    private func decodedResponse<Response: Decodable>(for request: URLRequest, failure: NotifierError) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw failure
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw failure
        }
    }

    private static func formBody(_ values: [String: String]) -> Data {
        values
            .map { key, value in
                "\(key.urlFormEncoded)=\(value.urlFormEncoded)"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    private static func secureRandomString(length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static let rfc3339Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}


final class GoogleOAuthLoopbackServer: @unchecked Sendable {
    let redirectURI: String

    private let listener: NWListener
    private let queue = DispatchQueue(label: "GoogleOAuthLoopbackServer")
    private var continuation: CheckedContinuation<GoogleOAuthRedirect, Error>?
    private var didResume = false

    init(port: NWEndpoint.Port = 53682) throws {
        listener = try NWListener(using: .tcp, on: port)
        redirectURI = "http://127.0.0.1:\(port.rawValue)/oauth2redirect"
    }

    func waitForRedirect() async throws -> GoogleOAuthRedirect {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                self.listener.stateUpdateHandler = { state in
                    guard case let .failed(error) = state else { return }
                    self.finish(with: .failure(error))
                }
                self.listener.newConnectionHandler = { connection in
                    self.handle(connection)
                }
                self.listener.start(queue: self.queue)
            }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.finish(with: .failure(error))
                return
            }
            guard let data, let request = String(data: data, encoding: .utf8), let firstLine = request.components(separatedBy: "\r\n").first else {
                self.finish(with: .failure(NotifierError.googleCalendarAuthenticationFailed))
                return
            }
            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2,
                  let url = URL(string: "http://127.0.0.1\(parts[1])"),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                self.sendResponse(connection, success: false)
                self.finish(with: .failure(NotifierError.googleCalendarAuthenticationFailed))
                return
            }
            let queryItems = components.queryItems ?? []
            if let errorValue = queryItems.first(where: { $0.name == "error" })?.value {
                self.sendResponse(connection, success: false)
                self.finish(with: .failure(NotifierError.googleCalendarOAuthDenied(errorValue)))
                return
            }
            guard let code = queryItems.first(where: { $0.name == "code" })?.value,
                  let state = queryItems.first(where: { $0.name == "state" })?.value else {
                self.sendResponse(connection, success: false)
                self.finish(with: .failure(NotifierError.googleCalendarAuthenticationFailed))
                return
            }
            self.sendResponse(connection, success: true)
            self.finish(with: .success(GoogleOAuthRedirect(code: code, state: state)))
        }
    }

    private func sendResponse(_ connection: NWConnection, success: Bool) {
        let title = success ? "Google Calendar connected" : "Google Calendar connection failed"
        let body = success ? "You can close this browser tab and return to Kakitangan Companion." : "Return to Kakitangan Companion and try connecting again."
        let html = """
        <!doctype html><html><head><meta charset=\"utf-8\"><title>\(title)</title></head><body style=\"font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:48px;line-height:1.5\"><h1>\(title)</h1><p>\(body)</p></body></html>
        """
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(with result: Result<GoogleOAuthRedirect, Error>) {
        guard !didResume else { return }
        didResume = true
        listener.cancel()
        switch result {
        case let .success(redirect):
            continuation?.resume(returning: redirect)
        case let .failure(error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}


struct GoogleOAuthRedirect {
    let code: String
    let state: String
}


struct GoogleCalendarTokenSet: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}


private struct GoogleUserInfoResponse: Decodable {
    let email: String
}


private struct GoogleCalendarEventsResponse: Decodable {
    let items: [GoogleCalendarEventResponse]
}


private struct GoogleCalendarEventResponse: Decodable {
    let id: String
    let summary: String?
    let start: GoogleCalendarEventDate
    let end: GoogleCalendarEventDate
    let location: String?
    let hangoutLink: String?
    let htmlLink: String?
    let organizer: GoogleCalendarPerson?
    let attendees: [GoogleCalendarPerson]?

    func event(ownerEmail: String) -> GoogleCalendarEvent? {
        guard let startDate = start.resolvedDate, let endDate = end.resolvedDate else {
            return nil
        }
        return GoogleCalendarEvent(
            id: id,
            title: summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? summary! : "Untitled meeting",
            startDate: startDate,
            endDate: endDate,
            isAllDay: start.date != nil,
            location: location,
            meetingLink: URL(string: hangoutLink ?? htmlLink ?? ""),
            organizerEmail: organizer?.email,
            attendeeEmails: attendees?.compactMap(\.email) ?? [],
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
}


private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlFormAllowed) ?? self
    }
}


private extension CharacterSet {
    static let urlFormAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return allowed
    }()
}


private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
