import Foundation


/// A bookable Google Workspace room. Rooms are invited as `resource` attendees.
struct MeetingRoom: Identifiable, Hashable {
    static let resourceCalendarSuffix = "@resource.calendar.google.com"

    let email: String
    let name: String

    var id: String { email.lowercased() }
}


/// A person who can be added as a meeting guest, tagged with where the suggestion came from.
struct GuestSuggestion: Identifiable, Hashable {
    /// Ordered by trust: people you work with directly rank above broader address books.
    enum Source: Int, Comparable {
        case kakitangan
        case meetingHistory
        case directory
        case googleContacts
        case macContacts

        static func < (lhs: Source, rhs: Source) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var icon: String {
            switch self {
            case .kakitangan:
                return "person.2"
            case .meetingHistory:
                return "clock.arrow.circlepath"
            case .directory:
                return "building.2"
            case .googleContacts:
                return "person.crop.circle"
            case .macContacts:
                return "book.closed"
            }
        }

        var title: String {
            switch self {
            case .kakitangan:
                return "Kakitangan"
            case .meetingHistory:
                return "Met before"
            case .directory:
                return "Directory"
            case .googleContacts:
                return "Google contacts"
            case .macContacts:
                return "Contacts"
            }
        }
    }

    let email: String
    let name: String?
    let source: Source

    var id: String { email.lowercased() }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? email : trimmed
    }
}


/// Shared text matching for every autocomplete list, so guests, rooms, and places rank alike.
enum SuggestionMatcher {
    /// Lower is better: 0 = whole field starts with the query, 1 = a word starts with it,
    /// 2 = it appears anywhere. `nil` means no match.
    static func score(_ query: String, in fields: [String?]) -> Int? {
        let needle = normalized(query)
        guard !needle.isEmpty else {
            return nil
        }
        var best: Int?
        for field in fields.compactMap({ $0 }) {
            let haystack = normalized(field)
            let fieldScore: Int?
            if haystack.hasPrefix(needle) {
                fieldScore = 0
            } else if haystack
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .contains(where: { $0.hasPrefix(needle) }) {
                fieldScore = 1
            } else if haystack.contains(needle) {
                fieldScore = 2
            } else {
                fieldScore = nil
            }
            if let fieldScore, fieldScore < (best ?? .max) {
                best = fieldScore
            }
        }
        return best
    }

    /// Ranks guests by match quality, then source, then their order within the source (which
    /// callers pre-sort, e.g. by how often you've met). Each email appears once, keeping the best
    /// entry but borrowing a name from another source when the best one has none.
    static func rankGuests(_ candidates: [GuestSuggestion], matching query: String, excluding excluded: Set<String>, limit: Int) -> [GuestSuggestion] {
        var namesByID: [String: String] = [:]
        for candidate in candidates where namesByID[candidate.id] == nil {
            if let name = candidate.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                namesByID[candidate.id] = name
            }
        }

        let scored = candidates.enumerated().compactMap { index, candidate -> (score: Int, index: Int, guest: GuestSuggestion)? in
            guard !excluded.contains(candidate.id),
                  let score = score(query, in: [candidate.name, candidate.email]) else {
                return nil
            }
            return (score, index, candidate)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score < rhs.score
            }
            if lhs.guest.source != rhs.guest.source {
                return lhs.guest.source < rhs.guest.source
            }
            return lhs.index < rhs.index
        }

        var seen: Set<String> = []
        var ranked: [GuestSuggestion] = []
        for entry in scored where seen.insert(entry.guest.id).inserted {
            let guest = entry.guest
            ranked.append(GuestSuggestion(email: guest.email, name: guest.name ?? namesByID[guest.id], source: guest.source))
            if ranked.count == limit {
                break
            }
        }
        return ranked
    }

    /// Orders values by how often they occur (most first), ties broken alphabetically.
    static func byFrequency<Key: Hashable>(_ values: [Key], name: (Key) -> String) -> [Key] {
        let counts = values.reduce(into: [Key: Int]()) { $0[$1, default: 0] += 1 }
        return counts.keys.sorted { lhs, rhs in
            if counts[lhs] != counts[rhs] {
                return counts[lhs, default: 0] > counts[rhs, default: 0]
            }
            return name(lhs).localizedCaseInsensitiveCompare(name(rhs)) == .orderedAscending
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
