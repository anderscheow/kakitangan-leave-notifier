import Foundation


/// Google People API lookups for guest autocomplete: the Workspace directory and the
/// auto-collected "Other contacts" (people you've emailed).
@MainActor
final class GooglePeopleService {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Prefix search over the signed-in user's Workspace domain. Personal Gmail accounts have no
    /// directory, so Google answers with an error that callers should treat as "no results".
    func searchDirectory(query: String, accessToken: String) async throws -> [GuestSuggestion] {
        let response: PeopleSearchResponse = try await get(
            path: "people:searchDirectoryPeople",
            query: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "readMask", value: "names,emailAddresses"),
                URLQueryItem(name: "sources", value: "DIRECTORY_SOURCE_TYPE_DOMAIN_PROFILE"),
                URLQueryItem(name: "pageSize", value: "10"),
            ],
            accessToken: accessToken,
        )
        return (response.people ?? []).flatMap { $0.suggestions(source: .directory) }
    }

    /// Google recommends an empty-query call first so its search cache is fresh.
    func warmUpOtherContacts(accessToken: String) async {
        _ = try? await searchOtherContacts(query: "", accessToken: accessToken)
    }

    func searchOtherContacts(query: String, accessToken: String) async throws -> [GuestSuggestion] {
        let response: OtherContactsSearchResponse = try await get(
            path: "otherContacts:search",
            query: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "readMask", value: "names,emailAddresses"),
                URLQueryItem(name: "pageSize", value: "10"),
            ],
            accessToken: accessToken,
        )
        return (response.results ?? []).flatMap { $0.person.suggestions(source: .googleContacts) }
    }

    private func get<Response: Decodable>(path: String, query: [URLQueryItem], accessToken: String) async throws -> Response {
        var components = URLComponents(string: "https://people.googleapis.com/v1/\(path)")
        components?.queryItems = query
        guard let url = components?.url else {
            throw NotifierError.googleCalendarRequestFailed
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotifierError.googleCalendarRequestFailed
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = (try? decoder.decode(PeopleErrorResponse.self, from: data))?.error.message
            throw NotifierError.googleCalendarRequestFailedDetail("People API HTTP \(httpResponse.statusCode): \(message ?? "no details")")
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw NotifierError.googleCalendarResponseDecodingFailed(error.localizedDescription)
        }
    }
}


private struct PeopleSearchResponse: Decodable {
    let people: [PeoplePerson]?
}


private struct OtherContactsSearchResponse: Decodable {
    let results: [Result]?

    struct Result: Decodable {
        let person: PeoplePerson
    }
}


private struct PeoplePerson: Decodable {
    let names: [Name]?
    let emailAddresses: [EmailAddress]?

    struct Name: Decodable {
        let displayName: String?
    }

    struct EmailAddress: Decodable {
        let value: String?
    }

    func suggestions(source: GuestSuggestion.Source) -> [GuestSuggestion] {
        let name = names?.first?.displayName
        return (emailAddresses ?? [])
            .compactMap(\.value)
            .filter { $0.contains("@") }
            .map { GuestSuggestion(email: $0, name: name, source: source) }
    }
}


private struct PeopleErrorResponse: Decodable {
    let error: Detail

    struct Detail: Decodable {
        let message: String
    }
}
