import SwiftUI


/// Google Calendar–style event editor: time, repeat, guests with free/busy, Meet, and invites.
struct NewMeetingSheet: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var suggestions: MeetingSuggestionStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft = MeetingDraft()
    @State private var guestQuery = ""
    @State private var guestInputError: String?
    @State private var availability: [String: GuestAvailability] = [:]
    @State private var availabilityCheckedFor: AvailabilityRequest?
    @State private var isCheckingAvailability = false
    @State private var availabilityError: String?
    @State private var createError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Add title", text: $draft.title)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)

                    MeetingFormSection(title: "When", icon: "clock") {
                        scheduleFields
                    }
                    MeetingFormSection(title: "Guests", icon: "person.2") {
                        guestFields
                    }
                    MeetingFormSection(title: "Details", icon: "text.alignleft") {
                        detailFields
                    }
                }
                .padding(24)
            }

            Divider()

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 540, height: 660)
        .background(Color.leaveCanvas)
        .task {
            await model.loadManagedEmployeesIfNeeded()
        }
        .task {
            await suggestions.prepare(upcomingEvents: model.calendarEvents)
        }
    }

    // MARK: - When

    @ViewBuilder
    private var scheduleFields: some View {
        Toggle("All day", isOn: $draft.isAllDay)

        DatePicker("Starts", selection: startBinding, displayedComponents: dateComponents)
        DatePicker("Ends", selection: $draft.endDate, displayedComponents: dateComponents)

        Picker("Repeat", selection: $draft.recurrence.frequency) {
            ForEach(MeetingRecurrenceFrequency.allCases) { frequency in
                Text(frequency.title).tag(frequency)
            }
        }

        if draft.recurrence.repeats {
            HStack(spacing: 12) {
                Picker("Ends", selection: $draft.recurrence.end) {
                    ForEach(MeetingRecurrenceEnd.allCases) { end in
                        Text(end.title).tag(end)
                    }
                }
                .fixedSize()

                switch draft.recurrence.end {
                case .never:
                    EmptyView()
                case .onDate:
                    DatePicker("End date", selection: $draft.recurrence.endDate, displayedComponents: .date)
                        .labelsHidden()
                case .afterOccurrences:
                    Stepper(
                        "\(draft.recurrence.occurrenceCount) occurrence\(draft.recurrence.occurrenceCount == 1 ? "" : "s")",
                        value: $draft.recurrence.occurrenceCount,
                        in: MeetingRecurrence.occurrenceRange,
                    )
                }
            }
        }
    }

    private var dateComponents: DatePickerComponents {
        draft.isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    /// Moving the start drags the end along so the meeting keeps its length.
    private var startBinding: Binding<Date> {
        Binding(
            get: { draft.startDate },
            set: { draft.moveStart(to: $0) },
        )
    }

    // MARK: - Guests

    @ViewBuilder
    private var guestFields: some View {
        GuestAutocompleteField(
            draft: $draft,
            query: $guestQuery,
            inputError: $guestInputError,
            suggestions: suggestions,
            employees: model.allManagedEmployees,
        )

        moreSuggestionsControls

        if let ownerAvailability {
            HStack(spacing: 8) {
                Text("Your calendar")
                    .font(.caption)
                    .foregroundStyle(Color.leaveMuted)
                GuestAvailabilityBadge(availability: ownerAvailability)
            }
        }

        ForEach(draft.guestEmails, id: \.self) { email in
            guestRow(email)
        }

        availabilityControls

        Toggle("Send invitations to guests", isOn: $draft.sendsInvitations)
            .disabled(!draft.canSendInvitations)
    }

    private func guestRow(_ email: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(Color.leaveTeal)
            VStack(alignment: .leading, spacing: 1) {
                Text(guestName(for: email) ?? email)
                    .font(.subheadline)
                    .foregroundStyle(Color.leaveInk)
                    .lineLimit(1)
                if guestName(for: email) != nil {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(Color.leaveMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let status = currentAvailability(for: email) {
                GuestAvailabilityBadge(availability: status)
            }
            Button {
                draft.removeGuest(email)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.liquidGlass)
            .controlSize(.small)
            .accessibilityLabel("Remove \(email)")
        }
    }

    @ViewBuilder
    private var availabilityControls: some View {
        if !draft.availabilityEmails.isEmpty {
            HStack(spacing: 10) {
                Button {
                    checkAvailability()
                } label: {
                    Label(isAvailabilityCurrent ? "Recheck availability" : "Check availability", systemImage: "calendar.badge.clock")
                }
                .buttonStyle(.liquidGlass)
                .controlSize(.small)
                .disabled(isCheckingAvailability || draft.validationMessage() != nil)

                if isCheckingAvailability {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let availabilityError {
                Text(availabilityError)
                    .font(.caption)
                    .foregroundStyle(Color.leaveOrange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if draft.recurrence.repeats {
                Text("Availability covers the first meeting in the series.")
                    .font(.caption)
                    .foregroundStyle(Color.leaveMuted)
            }
        }
    }

    private func guestName(for email: String) -> String? {
        suggestions.displayName(for: email, employees: model.allManagedEmployees)
    }

    /// Offers the optional sources that need consent. Hidden once each is granted or declined.
    @ViewBuilder
    private var moreSuggestionsControls: some View {
        let needsGoogle = model.isGoogleCalendarConnected && !suggestions.hasAllGoogleSuggestionScopes
        let needsContacts = suggestions.macContactsAccess == .notDetermined
        if needsGoogle || needsContacts {
            HStack(spacing: 8) {
                Text("More suggestions:")
                    .font(.caption)
                    .foregroundStyle(Color.leaveMuted)
                if needsGoogle {
                    Button {
                        Task { await suggestions.connectGoogleSuggestions(upcomingEvents: model.calendarEvents) }
                    } label: {
                        Label("Google directory & rooms", systemImage: "building.2")
                    }
                    .buttonStyle(.liquidGlass)
                    .controlSize(.small)
                    .disabled(suggestions.isConnectingGoogle)
                    .help("Search your Workspace directory and Google contacts, and list room calendars you've added.")
                }
                if needsContacts {
                    Button {
                        Task { await suggestions.connectMacContacts() }
                    } label: {
                        Label("Mac Contacts", systemImage: "book.closed")
                    }
                    .buttonStyle(.liquidGlass)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Availability

    private var currentRequest: AvailabilityRequest {
        AvailabilityRequest(interval: draft.occupiedInterval(), guests: draft.availabilityEmails.map { $0.lowercased() })
    }

    /// Results are only shown while the time and guest list still match what was checked.
    private var isAvailabilityCurrent: Bool {
        availabilityCheckedFor == currentRequest
    }

    private func currentAvailability(for email: String) -> GuestAvailability? {
        guard isAvailabilityCurrent else {
            return nil
        }
        return availability[email.lowercased()]
    }

    private var ownerAvailability: GuestAvailability? {
        let ownerEmail = model.googleCalendar.ownerEmail
        guard !ownerEmail.isEmpty, !draft.hasGuest(ownerEmail) else {
            return nil
        }
        return currentAvailability(for: ownerEmail)
    }

    private func checkAvailability() {
        let request = currentRequest
        isCheckingAvailability = true
        availabilityError = nil
        Task {
            defer { isCheckingAvailability = false }
            do {
                availability = try await model.guestAvailability(for: draft)
                availabilityCheckedFor = request
            } catch {
                availabilityError = error.localizedDescription
            }
        }
    }

    // MARK: - Details

    @ViewBuilder
    private var detailFields: some View {
        Toggle("Add Google Meet video conferencing", isOn: $draft.addsGoogleMeet)

        LocationAutocompleteField(draft: $draft, suggestions: suggestions)

        ForEach(draft.rooms) { room in
            roomRow(room)
        }

        TextEditor(text: $draft.notes)
            .font(.body)
            .frame(minHeight: 80)
            .overlay(alignment: .topLeading) {
                if draft.notes.isEmpty {
                    Text("Add description")
                        .foregroundStyle(Color.leaveMuted)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.leaveTeal.opacity(0.16), lineWidth: 1)
            }
    }

    private func roomRow(_ room: MeetingRoom) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "building.2")
                .foregroundStyle(Color.leaveTeal)
            Text(room.name)
                .font(.subheadline)
                .foregroundStyle(Color.leaveInk)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let status = currentAvailability(for: room.email) {
                GuestAvailabilityBadge(availability: status)
            }
            Button {
                draft.removeRoom(room)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.liquidGlass)
            .controlSize(.small)
            .accessibilityLabel("Remove room \(room.name)")
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if let message = createError ?? draft.validationMessage() {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.leaveOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.liquidGlass)
            .keyboardShortcut(.cancelAction)

            // ⌘↩ rather than ↩, because Return in the guest field adds a guest.
            Button {
                create()
            } label: {
                if model.isCreatingMeeting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Create")
                }
            }
            .buttonStyle(.liquidGlassProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.isCreatingMeeting || draft.validationMessage() != nil)
            .help("Create meeting (⌘↩)")
        }
    }

    private func create() {
        // Don't silently drop an address that was typed but not yet committed.
        guestInputError = GuestAutocompleteField.commit(query: &guestQuery, into: &draft)
        guard guestInputError == nil else {
            return
        }
        createError = nil
        Task {
            if await model.createMeeting(draft) {
                dismiss()
            } else {
                createError = model.statusMessage
            }
        }
    }
}


private struct AvailabilityRequest: Equatable {
    let interval: DateInterval
    let guests: [String]
}


private struct MeetingFormSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(Color.leaveInk)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassSurface(cornerRadius: 14)
        }
    }
}


private struct GuestAvailabilityBadge: View {
    let availability: GuestAvailability

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .liquidGlassCapsule(tint: color)
            .help(helpText)
    }

    private var text: String {
        switch availability {
        case .free:
            return "Free"
        case let .busy(periods):
            guard let first = periods.first else {
                return "Busy"
            }
            let range = "\(first.start.formatted(date: .omitted, time: .shortened))–\(first.end.formatted(date: .omitted, time: .shortened))"
            return periods.count > 1 ? "Busy \(range) +\(periods.count - 1)" : "Busy \(range)"
        case .unknown:
            return "Unknown"
        }
    }

    private var helpText: String {
        switch availability {
        case .free:
            return "No conflicts during this meeting."
        case let .busy(periods):
            return periods
                .map { "\($0.start.formatted(date: .abbreviated, time: .shortened)) – \($0.end.formatted(date: .omitted, time: .shortened))" }
                .joined(separator: "\n")
        case let .unknown(reason):
            return "Availability unavailable: \(reason)"
        }
    }

    private var color: Color {
        switch availability {
        case .free:
            return .leaveTeal
        case .busy:
            return .leaveOrange
        case .unknown:
            return .leaveMuted
        }
    }
}
