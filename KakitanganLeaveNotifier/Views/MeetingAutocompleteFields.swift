import SwiftUI


/// Guest entry with suggestions from Kakitangan, past meetings, Google, and Mac Contacts.
/// Return adds the top suggestion for a name, or parses typed email addresses.
struct GuestAutocompleteField: View {
    @Binding var draft: MeetingDraft
    @Binding var query: String
    @Binding var inputError: String?
    @ObservedObject var suggestions: MeetingSuggestionStore
    let employees: [ManagedEmployee]

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Guests", text: $query, prompt: .leavePrompt("Add guests by name or email"))
                .focused($isFocused)
                .onSubmit(commit)
                .onChange(of: query) { newValue in
                    suggestions.searchPeople(newValue)
                }
                .leaveInputField()

            if let inputError {
                Text(inputError)
                    .font(.caption)
                    .foregroundStyle(Color.leaveOrange)
            }

            if isFocused, !matches.isEmpty {
                SuggestionList {
                    ForEach(matches) { guest in
                        SuggestionRow(
                            icon: guest.source.icon,
                            title: guest.displayName,
                            subtitle: guest.name == nil ? guest.source.title : "\(guest.email) · \(guest.source.title)",
                        ) {
                            add(guest.email)
                        }
                    }
                }
                .leaveTransition()
            }

            if isFocused, let error = suggestions.remoteSearchError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.leaveMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .leaveAnimation(LeaveMotion.quick, value: isFocused && !matches.isEmpty)
    }

    private var matches: [GuestSuggestion] {
        suggestions.guestSuggestions(matching: query, employees: employees, excluding: draft)
    }

    private func commit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !trimmed.contains("@"), let best = matches.first {
            add(best.email)
            return
        }
        inputError = GuestAutocompleteField.commit(query: &query, into: &draft)
    }

    private func add(_ email: String) {
        draft.addGuests(from: email)
        query = ""
        inputError = nil
    }

    /// Adds every valid address in `query`, leaves rejected text in place, and returns an error
    /// message for it. Shared with Create so typed-but-uncommitted guests aren't lost.
    static func commit(query: inout String, into draft: inout MeetingDraft) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let rejected = draft.addGuests(from: trimmed)
        query = rejected.joined(separator: ", ")
        return rejected.isEmpty ? nil : "Not an email address: \(rejected.joined(separator: ", "))"
    }
}


/// Location entry offering rooms (which get booked), places you've met before, and Apple Maps.
struct LocationAutocompleteField: View {
    @Binding var draft: MeetingDraft
    @ObservedObject var suggestions: MeetingSuggestionStore

    @StateObject private var places = PlaceSearchCompleter()
    @FocusState private var isFocused: Bool
    /// The last value picked from the list, so choosing a suggestion closes the list.
    @State private var acceptedLocation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Location", text: $draft.location, prompt: .leavePrompt("Add location or room"))
                .focused($isFocused)
                .onChange(of: draft.location) { newValue in
                    places.update(query: newValue == acceptedLocation ? "" : newValue)
                }
                .leaveInputField()

            if isFocused, draft.location != acceptedLocation, hasSuggestions {
                SuggestionList {
                    if !roomMatches.isEmpty {
                        SuggestionSectionHeader(title: "Rooms")
                        ForEach(roomMatches) { room in
                            SuggestionRow(icon: "building.2", title: room.name, subtitle: "Book this room") {
                                draft.addRoom(room)
                                accept(room.name)
                            }
                        }
                    }
                    if !recentMatches.isEmpty {
                        SuggestionSectionHeader(title: "Used before")
                        ForEach(recentMatches, id: \.self) { location in
                            SuggestionRow(icon: "clock.arrow.circlepath", title: location, subtitle: nil) {
                                draft.location = location
                                accept(location)
                            }
                        }
                    }
                    if !places.results.isEmpty {
                        SuggestionSectionHeader(title: "Places")
                        ForEach(places.results) { place in
                            SuggestionRow(icon: "mappin.and.ellipse", title: place.title, subtitle: place.subtitle.isEmpty ? nil : place.subtitle) {
                                draft.location = place.locationText
                                accept(place.locationText)
                            }
                        }
                    }
                }
                .leaveTransition()
            }
        }
        .leaveAnimation(LeaveMotion.quick, value: isFocused && draft.location != acceptedLocation && hasSuggestions)
    }

    private var roomMatches: [MeetingRoom] {
        suggestions.roomSuggestions(matching: draft.location, excluding: draft)
    }

    private var recentMatches: [String] {
        suggestions.locationSuggestions(matching: draft.location)
    }

    private var hasSuggestions: Bool {
        !roomMatches.isEmpty || !recentMatches.isEmpty || !places.results.isEmpty
    }

    private func accept(_ location: String) {
        acceptedLocation = location
        places.update(query: "")
        isFocused = false
    }
}


private struct SuggestionList<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            content
        }
        .padding(.vertical, 4)
        .background(Color.leaveSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.leaveBorder, lineWidth: 1)
        }
        .shadow(color: Color.leaveShadow, radius: 8, y: 3)
    }
}


private struct SuggestionSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.leaveMuted)
            .padding(.horizontal, 10)
            .padding(.top, 4)
    }
}


private struct SuggestionRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Color.leaveAccent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(Color.leaveInk)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.leaveMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .leaveHoverHighlight(cornerRadius: 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
