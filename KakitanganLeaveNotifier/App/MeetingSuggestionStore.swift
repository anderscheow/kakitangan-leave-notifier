import AppKit
import Foundation


/// Autocomplete data for the New Meeting sheet. Lives for the app session so reopening the sheet
/// doesn't refetch history; everything here is best-effort and never blocks creating a meeting.
@MainActor
final class MeetingSuggestionStore: ObservableObject {
    @Published private(set) var historyGuests: [GuestSuggestion] = []
    @Published private(set) var recentLocations: [String] = []
    @Published private(set) var rooms: [MeetingRoom] = []
    @Published private(set) var macContacts: [GuestSuggestion] = []
    @Published private(set) var remoteGuests: [GuestSuggestion] = []
    @Published private(set) var grantedGoogleScopes: Set<String> = []
    @Published private(set) var macContactsAccess: MacContactsService.Access = MacContactsService.access
    @Published private(set) var isConnectingGoogle = false
    @Published private(set) var remoteSearchError: String?

    private static let historyDays = 90
    private static let historyLifetime: TimeInterval = 10 * 60
    private static let searchDebounceNanoseconds: UInt64 = 250_000_000

    private let calendarService = GoogleCalendarService()
    private let peopleService = GooglePeopleService()
    private var historyLoadedAt: Date?
    private var historyRooms: [MeetingRoom] = []
    private var subscribedRooms: [MeetingRoom] = []
    private var searchTask: Task<Void, Never>?

    var canSearchDirectory: Bool {
        grantedGoogleScopes.contains(GoogleCalendarService.directoryScope)
    }

    var canSearchGoogleContacts: Bool {
        grantedGoogleScopes.contains(GoogleCalendarService.otherContactsScope)
    }

    var canListSubscribedRooms: Bool {
        grantedGoogleScopes.contains(GoogleCalendarService.calendarListScope)
    }

    var hasAllGoogleSuggestionScopes: Bool {
        GoogleCalendarService.suggestionScopes.allSatisfy(grantedGoogleScopes.contains)
    }

    // MARK: - Loading

    /// Refreshes cached sources. `upcomingEvents` is the dashboard's already-loaded list, merged
    /// with the fetched history so future meetings count too.
    func prepare(upcomingEvents: [GoogleCalendarEvent]) async {
        macContactsAccess = MacContactsService.access
        if macContactsAccess == .authorized, macContacts.isEmpty {
            macContacts = await MacContactsService.loadSuggestions()
        }

        guard let user = try? await calendarService.currentOrRestoredUser() else {
            return
        }
        grantedGoogleScopes = calendarService.grantedScopes(of: user)
        guard let accessToken = try? await calendarService.accessToken(for: user) else {
            return
        }

        if historyLoadedAt.map({ Date().timeIntervalSince($0) > Self.historyLifetime }) ?? true {
            let history = (try? await calendarService.fetchEventHistory(
                accessToken: accessToken,
                ownerEmail: calendarService.ownerEmail(for: user),
                daysBack: Self.historyDays,
            )) ?? []
            applyHistory(history + upcomingEvents)
            historyLoadedAt = Date()
        }

        if canListSubscribedRooms, subscribedRooms.isEmpty {
            subscribedRooms = (try? await calendarService.fetchSubscribedRooms(accessToken: accessToken)) ?? []
            mergeRooms()
        }
        if canSearchGoogleContacts {
            await peopleService.warmUpOtherContacts(accessToken: accessToken)
        }
    }

    /// One consent prompt for directory, Google contacts, and subscribed rooms.
    func connectGoogleSuggestions(upcomingEvents: [GoogleCalendarEvent]) async {
        guard !isConnectingGoogle else {
            return
        }
        isConnectingGoogle = true
        defer { isConnectingGoogle = false }
        do {
            let user = try await calendarService.userWithSuggestionScopes(
                calendarService.currentOrRestoredUser(),
                presenting: NSApp.oauthPresentationWindow,
            )
            grantedGoogleScopes = calendarService.grantedScopes(of: user)
            remoteSearchError = hasAllGoogleSuggestionScopes ? nil : "Some Google suggestion permissions were not granted."
        } catch {
            remoteSearchError = error.localizedDescription
        }
        await prepare(upcomingEvents: upcomingEvents)
    }

    func connectMacContacts() async {
        macContactsAccess = await MacContactsService.requestAccess()
        if macContactsAccess == .authorized {
            macContacts = await MacContactsService.loadSuggestions()
        }
    }

    private func applyHistory(_ events: [GoogleCalendarEvent]) {
        let attended = events.filter { !$0.isCancelled }
        let people = attended.flatMap { $0.attendees.filter { !$0.isSelf && !$0.isResource } }
        let namesByID = Dictionary(people.map { ($0.id, $0.displayName) }, uniquingKeysWith: { $0 ?? $1 })
        let emailsByID = Dictionary(people.map { ($0.id, $0.email) }, uniquingKeysWith: { first, _ in first })
        historyGuests = SuggestionMatcher.byFrequency(people.map(\.id)) { emailsByID[$0] ?? $0 }
            .compactMap { id in
                emailsByID[id].map { GuestSuggestion(email: $0, name: namesByID[id] ?? nil, source: .meetingHistory) }
            }

        let roomAttendees = attended.flatMap { $0.attendees.filter(\.isResource) }
        let roomsByID = Dictionary(roomAttendees.map { ($0.id, MeetingRoom(email: $0.email, name: $0.name)) }, uniquingKeysWith: { first, _ in first })
        historyRooms = SuggestionMatcher.byFrequency(roomAttendees.map(\.id)) { roomsByID[$0]?.name ?? $0 }
            .compactMap { roomsByID[$0] }
        mergeRooms()

        let locations = attended
            .compactMap { $0.location?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        recentLocations = SuggestionMatcher.byFrequency(locations) { $0 }
    }

    /// Rooms you've actually used first, then the rest of your subscribed rooms alphabetically.
    private func mergeRooms() {
        let used = Set(historyRooms.map(\.id))
        rooms = historyRooms + subscribedRooms
            .filter { !used.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Guests

    /// Debounced People API search; results land in `remoteGuests` for the latest query only.
    func searchPeople(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, canSearchDirectory || canSearchGoogleContacts else {
            remoteGuests = []
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.searchDebounceNanoseconds)
            guard let self, !Task.isCancelled else {
                return
            }
            let results = await self.fetchRemoteGuests(matching: trimmed)
            guard !Task.isCancelled else {
                return
            }
            self.remoteGuests = results
        }
    }

    private func fetchRemoteGuests(matching query: String) async -> [GuestSuggestion] {
        guard let user = try? await calendarService.currentOrRestoredUser(),
              let accessToken = try? await calendarService.accessToken(for: user) else {
            return []
        }
        var results: [GuestSuggestion] = []
        var errors: [String] = []
        let attemptedSources = [canSearchDirectory, canSearchGoogleContacts].filter { $0 }.count
        if canSearchDirectory {
            do {
                results += try await peopleService.searchDirectory(query: query, accessToken: accessToken)
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        if canSearchGoogleContacts {
            do {
                results += try await peopleService.searchOtherContacts(query: query, accessToken: accessToken)
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        // Only surface a failure when every source failed (e.g. People API not enabled in GCP);
        // a personal Gmail account's missing directory alone shouldn't show an error.
        remoteSearchError = errors.count == attemptedSources ? errors.first : nil
        return results
    }

    func guestSuggestions(matching query: String, employees: [ManagedEmployee], excluding draft: MeetingDraft, limit: Int = 8) -> [GuestSuggestion] {
        let kakitangan = employees.map { GuestSuggestion(email: $0.email, name: $0.displayName, source: .kakitangan) }
        return SuggestionMatcher.rankGuests(
            kakitangan + historyGuests + remoteGuests + macContacts,
            matching: query,
            excluding: Set(draft.guestEmails.map { $0.lowercased() }),
            limit: limit,
        )
    }

    /// Best-known display name for a guest email from any source.
    func displayName(for email: String, employees: [ManagedEmployee]) -> String? {
        let id = email.lowercased()
        if let employee = employees.first(where: { $0.id == id }) {
            return employee.displayName
        }
        return (historyGuests + remoteGuests + macContacts)
            .first { $0.id == id && $0.name?.isEmpty == false }?
            .name
    }

    // MARK: - Locations

    /// With an empty query, shows your most-used rooms so the list is useful before typing.
    func roomSuggestions(matching query: String, excluding draft: MeetingDraft, limit: Int = 5) -> [MeetingRoom] {
        let available = rooms.filter { !draft.rooms.contains($0) }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Array(available.prefix(3))
        }
        return available
            .compactMap { room in SuggestionMatcher.score(query, in: [room.name]).map { (room, $0) } }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    func locationSuggestions(matching query: String, limit: Int = 4) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let roomNames = Set(rooms.map(\.name))
        let candidates = recentLocations.filter { !roomNames.contains($0) && $0 != trimmed }
        guard !trimmed.isEmpty else {
            return Array(candidates.prefix(3))
        }
        return candidates
            .compactMap { location in SuggestionMatcher.score(trimmed, in: [location]).map { (location, $0) } }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}
