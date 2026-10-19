import AppKit
import SwiftUI


/// "N attendees" label that opens the full guest list with each person's RSVP.
struct MeetingAttendeesButton: View {
    let event: GoogleCalendarEvent

    @State private var isPresented = false

    var body: some View {
        if event.attendees.isEmpty {
            Text(event.participantCountText)
        } else {
            Button {
                isPresented.toggle()
            } label: {
                Text(event.participantCountText)
                    .underline()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.leaveTeal)
            .help("Show attendees")
            .accessibilityLabel("Show \(event.participantCountText) for \(event.title)")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                MeetingAttendeesPopover(event: event)
            }
        }
    }
}


private struct MeetingAttendeesPopover: View {
    let event: GoogleCalendarEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(sortedAttendees) { attendee in
                        MeetingAttendeeRow(attendee: attendee)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 360)

            Divider()

            HStack {
                Spacer(minLength: 0)
                Button {
                    copyEmails()
                } label: {
                    Label("Copy emails", systemImage: "doc.on.doc")
                }
                .buttonStyle(.liquidGlass)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title)
                .font(.headline)
                .foregroundStyle(Color.leaveInk)
                .lineLimit(2)
            Text(event.participantCountText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.leaveInk)
            Text(responseSummary)
                .font(.caption)
                .foregroundStyle(Color.leaveMuted)
        }
    }

    /// e.g. "Accepted 3 · Maybe 1 · No response 2", skipping statuses nobody has.
    private var responseSummary: String {
        let order: [CalendarResponseStatus] = [.accepted, .tentative, .declined, .needsAction]
        return order
            .compactMap { status -> String? in
                let count = event.attendees.filter { $0.responseStatus == status }.count
                return count == 0 ? nil : "\(status.title) \(count)"
            }
            .joined(separator: " · ")
    }

    /// Organizer first, then by how committed each guest is, with rooms last.
    private var sortedAttendees: [GoogleCalendarAttendee] {
        event.attendees.sorted { lhs, rhs in
            if lhs.isResource != rhs.isResource {
                return !lhs.isResource
            }
            if lhs.isOrganizer != rhs.isOrganizer {
                return lhs.isOrganizer
            }
            if Self.rank(lhs.responseStatus) != Self.rank(rhs.responseStatus) {
                return Self.rank(lhs.responseStatus) < Self.rank(rhs.responseStatus)
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func rank(_ status: CalendarResponseStatus) -> Int {
        switch status {
        case .accepted:
            return 0
        case .tentative:
            return 1
        case .needsAction:
            return 2
        case .declined:
            return 3
        }
    }

    private func copyEmails() {
        let emails = sortedAttendees
            .filter { !$0.isResource }
            .map(\.email)
            .joined(separator: ", ")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(emails, forType: .string)
    }
}


private struct MeetingAttendeeRow: View {
    let attendee: GoogleCalendarAttendee

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: attendee.isResource ? "building.2" : attendee.responseStatus.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(attendee.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.leaveInk)
                        .lineLimit(1)
                    ForEach(badges, id: \.self) { badge in
                        MeetingAttendeeBadge(text: badge)
                    }
                }

                if attendee.name != attendee.email {
                    Text(attendee.email)
                        .font(.caption)
                        .foregroundStyle(Color.leaveMuted)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }

                Text(attendee.responseStatus.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)

                if let comment = attendee.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty {
                    Text("“\(comment)”")
                        .font(.caption)
                        .italic()
                        .foregroundStyle(Color.leaveMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var badges: [String] {
        var badges: [String] = []
        if attendee.isOrganizer {
            badges.append("Organizer")
        }
        if attendee.isSelf {
            badges.append("You")
        }
        if attendee.isOptional {
            badges.append("Optional")
        }
        if attendee.isResource {
            badges.append("Room")
        }
        return badges
    }

    private var statusColor: Color {
        switch attendee.responseStatus {
        case .accepted:
            return .leaveTeal
        case .declined:
            return .leaveOrange
        case .tentative, .needsAction:
            return .leaveMuted
        }
    }
}


private struct MeetingAttendeeBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.leaveInk)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .liquidGlassCapsule()
    }
}
