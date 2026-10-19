import AppKit
import SwiftUI


struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            LeaveBackdrop()

            switch model.screen {
            case .setup, .editing:
                SettingsView(isEditing: model.isEditing)
                    .transition(.opacity)
            case .dashboard:
                GeometryReader { proxy in
                    ScrollView {
                        DashboardView(width: proxy.size.width)
                            .padding(proxy.size.width < 640 ? 16 : 32)
                            .frame(maxWidth: 1120, alignment: .topLeading)
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
                .transition(.opacity)
            }
        }
        // Screen changes crossfade; a slide across the whole window would be more motion than it needs.
        .leaveAnimation(LeaveMotion.screen, value: model.screen)
        .task {
            await model.refreshNotificationPermission()
        }
        .task {
            await listenForDashboardRequests()
        }
        .sheet(isPresented: $model.isPresentingNewMeeting) {
            NewMeetingSheet(suggestions: model.meetingSuggestions)
                .environmentObject(model)
        }
        // Last in the chain so the sheet above inherits it too. Switches, segmented pickers,
        // steppers, glass buttons, and links follow the brand accent instead of macOS system blue.
        .tint(.leaveAccent)
    }

    /// Scoped to this view's lifetime, so a closed window never picks up menu shortcuts.
    private func listenForDashboardRequests() async {
        for await notification in NotificationCenter.default.notifications(named: .dashboardRequested) {
            if let request = notification.userInfo?[DashboardRequest.userInfoKey] as? DashboardRequest {
                model.handle(request)
            }
        }
    }
}


private struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    let isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 18)

            SectionTabView(selection: $model.settingsSection) { section in
                switch section {
                case .account:
                    settingsTab {
                        AccountCard()
                        MonitoredEmailsCard()
                    }
                case .calendar:
                    settingsTab {
                        GoogleCalendarCard()
                    }
                case .notifications:
                    settingsTab {
                        PermissionCard()
                        NotificationTimesCard()
                        OnDemandChecksCard()
                    }
                case .general:
                    settingsTab {
                        LoginItemCard()
                        AppVisibilityCard()
                        UpdatesCard()
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 20)

            footer
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            AppMark()

            VStack(alignment: .leading, spacing: 6) {
                Text(isEditing ? "Edit Kakitangan Companion" : "Set up Kakitangan Companion")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.leaveInk)

                Text(isEditing
                    ? "Update Kakitangan leave tracking, Google Calendar, notifications, or app behavior."
                    : "Track Kakitangan leave and your Google meetings from one calm weekday briefing.")
                    .font(.body)
                    .foregroundStyle(Color.leaveMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingsTab<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content()
            }
            // Combined with the outer inset this lines cards up with the header, and leaves room for card shadows.
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.statusMessage.isEmpty {
                StatusMessage(message: model.statusMessage)
                    .leaveTransition(edge: .bottom)
            }

            HStack(spacing: 12) {
                if isEditing {
                    Button("Cancel") {
                        model.cancelEditing()
                    }
                    .buttonStyle(.liquidGlass)
                    .controlSize(.large)
                }

                Button(isEditing ? "Save changes" : "Save setup") {
                    model.saveSetup()
                }
                .buttonStyle(.liquidGlassProminent)
                .controlSize(.large)

                Spacer(minLength: 0)
            }

            Text("Your password is saved only in the macOS Keychain. This app never displays or exports it.")
                .font(.caption)
                .foregroundStyle(Color.leaveMuted)
        }
        .leaveAnimation(value: model.statusMessage)
    }
}


/// Tab strip plus content, built from a SwiftUI segmented picker instead of
/// `TabView`. On macOS `TabView` is backed by `NSTabView`, whose tab labels can be
/// measured before the window has a real width and stay collapsed until clicked.
/// The content has no wrapping box, so cards sit directly on the window backdrop.
private struct SectionTabView<Section, Content>: View
where Section: RawRepresentable & CaseIterable & Identifiable & Hashable,
      Section.RawValue == String,
      Section.AllCases: RandomAccessCollection,
      Content: View {
    @Binding var selection: Section
    @ViewBuilder let content: (Section) -> Content

    var body: some View {
        VStack(spacing: 16) {
            Picker("Section", selection: $selection) {
                ForEach(Section.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .fixedSize()

            // A fresh identity per tab gives a short crossfade instead of a hard cut.
            content(selection)
                .id(selection)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .leaveAnimation(LeaveMotion.quick, value: selection)
    }
}


private struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    let width: CGFloat

    private var isCompact: Bool {
        width < 720
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            DashboardHeader(isCompact: isCompact)

            SectionTabView(selection: $model.dashboardSection) { section in
                switch section {
                case .overview:
                    DashboardOverview(isCompact: isCompact)
                case .meetings:
                    MeetingCalendarCard()
                case .leave:
                    LeaveListCard()
                }
            }

            if !model.statusMessage.isEmpty {
                StatusMessage(message: model.statusMessage)
                    .leaveTransition(edge: .bottom)
            }
        }
        .leaveAnimation(value: model.statusMessage)
        .task {
            await model.refreshWatchList()
        }
        .task {
            await model.startCalendarLiveWatch()
        }
    }
}


private struct DashboardHeader: View {
    @EnvironmentObject private var model: AppModel

    let isCompact: Bool

    var body: some View {
        if isCompact {
            VStack(alignment: .leading, spacing: 16) {
                titleContent
                actionBar
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                titleContent
                Spacer(minLength: 12)
                actionBar
            }
        }
    }

    private var titleContent: some View {
        HStack(alignment: .top, spacing: 16) {
            AppMark()

            VStack(alignment: .leading, spacing: 5) {
                Text("Kakitangan Companion")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.leaveInk)
                Text("Leave coverage and meeting context, ready when you are.")
                    .foregroundStyle(Color.leaveMuted)
            }
        }
    }

    private var actionBar: some View {
        GlassControlGroup(spacing: 10) {
            Button {
                Task {
                    await model.refreshWatchList()
                    await model.refreshCalendarEvents()
                }
            } label: {
                if model.isRefreshing || model.isRefreshingCalendar {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.liquidGlass)
            .controlSize(.large)
            .disabled(model.isRefreshing || model.isRefreshingCalendar)
            .help("Refresh leave and meetings")
            .accessibilityLabel("Refresh leave and meetings")

            Button {
                model.beginEditing()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.liquidGlass)
            .controlSize(.large)
            .help("Settings")
            .accessibilityLabel("Open settings")
        }
    }
}


extension DashboardRequest {
    /// Name of the place a request opens, for tooltips and VoiceOver hints.
    fileprivate var title: String {
        switch self {
        case let .section(section):
            return "\(section.rawValue) tab"
        case let .settings(section):
            return "\(section.rawValue) settings"
        case .newMeeting:
            return "New meeting"
        }
    }
}


private struct DashboardOverview: View {
    @EnvironmentObject private var model: AppModel

    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScheduleStatusCard()

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: isCompact ? 170 : 230), spacing: 16)],
                spacing: 16,
            ) {
                MetricCard(
                    title: "Accounts",
                    value: "\(model.configuredAccountCount)",
                    icon: "person.crop.circle",
                    destination: .settings(.account),
                )
                MetricCard(
                    title: "Watching",
                    value: "\(model.monitoredEmployeeCount) people",
                    icon: "person.2",
                    destination: .settings(.account),
                )
                MetricCard(
                    title: "Leave horizon",
                    value: "\(model.daysAhead) days",
                    icon: "calendar",
                    destination: .section(.leave),
                )
                MetricCard(
                    title: "Meetings",
                    value: model.isGoogleCalendarConnected ? "\(model.upcomingMeetingCount) upcoming" : "Not connected",
                    icon: "video",
                    tint: model.isGoogleCalendarConnected ? .leaveSuccess : .leaveOrange,
                    destination: meetingsDestination,
                )
                MetricCard(
                    title: "Cancelled",
                    value: model.cancelledMeetingCount == 0 ? "None" : "\(model.cancelledMeetingCount) meetings",
                    icon: "xmark.circle",
                    tint: model.cancelledMeetingCount == 0 ? .leaveMuted : .leaveOrange,
                    destination: meetingsDestination,
                )
                MetricCard(
                    title: "Reminders",
                    value: model.meetingReminderSummary,
                    icon: "bell.badge",
                    destination: .settings(.calendar),
                )
            }
        }
    }

    /// Meeting cards open the Meetings tab, or Calendar settings when there is nothing to show yet.
    private var meetingsDestination: DashboardRequest {
        model.isGoogleCalendarConnected ? .section(.meetings) : .settings(.calendar)
    }
}


private struct ScheduleStatusCard: View {
    @EnvironmentObject private var model: AppModel

    private let destination = DashboardRequest.settings(.notifications)

    var body: some View {
        // The card opens Notifications settings, while the schedule button keeps its own action. The
        // button is overlaid rather than nested in the card's button, and a hidden copy holds its space.
        Button {
            model.handle(destination)
        } label: {
            SurfaceCard {
                HStack(alignment: .center, spacing: 16) {
                    IconTile(systemName: scheduleIcon, color: scheduleColor, size: 46)
                        .leaveSymbolBounce(value: scheduleIcon)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(scheduleTitle)
                            .font(.headline)
                            .foregroundStyle(Color.leaveInk)
                        Text(scheduleDescription)
                            .font(.subheadline)
                            .foregroundStyle(Color.leaveMuted)
                    }

                    Spacer(minLength: 12)

                    CardChevron()

                    scheduleButton
                        .hidden()
                }
            }
        }
        .buttonStyle(.leaveCard)
        .help("Open \(destination.title)")
        .accessibilityLabel("\(scheduleTitle). \(scheduleDescription)")
        .accessibilityHint("Opens \(destination.title)")
        .overlay(alignment: .trailing) {
            scheduleButton
                .padding(.trailing, 20)
        }
        // The status color and copy change together when the schedule is enabled or goes stale.
        .leaveAnimation(value: scheduleIcon)
    }

    private var scheduleButton: some View {
        Button {
            model.installWeekdaySchedule()
        } label: {
            HStack(spacing: 6) {
                if model.isInstallingSchedule {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(scheduleButtonTitle)
            }
        }
        .buttonStyle(.liquidGlassProminent)
        .disabled(model.isInstallingSchedule || !model.hasAutomatedCheck)
    }

    private var scheduleDescription: String {
        if model.needsScheduleRefresh {
            return "Update the schedule to apply the saved check times and sign-in setting."
        }
        var descriptions: [String] = []
        if model.hasNotificationTimes {
            descriptions.append("weekdays at \(model.notificationScheduleSummary)")
        }
        if model.runAtLogin {
            descriptions.append("after you sign in")
        }
        guard !descriptions.isEmpty else {
            return "Add a time or enable Check at sign-in in Edit setup."
        }
        return "Runs \(descriptions.joined(separator: " and ")) on this Mac."
    }

    private var scheduleIcon: String {
        if model.needsScheduleRefresh {
            return "calendar.badge.exclamationmark"
        }
        return model.isWeekdayScheduleInstalled ? "calendar.badge.checkmark" : "calendar.badge.clock"
    }

    private var scheduleColor: Color {
        model.isWeekdayScheduleInstalled && !model.needsScheduleRefresh ? .leaveSuccess : .leaveOrange
    }

    private var scheduleTitle: String {
        if model.needsScheduleRefresh {
            return "Automatic checks need an update"
        }
        return model.isWeekdayScheduleInstalled ? "Automatic checks are active" : "Automatic checks are not scheduled"
    }

    private var scheduleButtonTitle: String {
        if model.needsScheduleRefresh {
            return "Update schedule"
        }
        return model.isWeekdayScheduleInstalled ? "Refresh schedule" : "Enable schedule"
    }
}


private enum MeetingGroupMode {
    case day
    case month
    case year

    init(daysAhead: Int) {
        if daysAhead <= 31 {
            self = .day
        } else if daysAhead <= 180 {
            self = .month
        } else {
            self = .year
        }
    }

    var title: String {
        switch self {
        case .day: return "day"
        case .month: return "month"
        case .year: return "year"
        }
    }
}


private struct MeetingGroup: Identifiable {
    let id: Date
    let title: String
    let events: [GoogleCalendarEvent]
}


private struct MeetingCalendarCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                MeetingCalendarHeader()
                MeetingCancelledBanner(cancelledCount: model.cancelledMeetingCount)
                MeetingCalendarContent(groups: groupedEvents)
            }
            // Meetings added, removed, or cancelled by a refresh ease in and out rather than popping.
            .leaveAnimation(value: model.calendarEvents)
        }
    }

    private var groupedEvents: [MeetingGroup] {
        let mode = MeetingGroupMode(daysAhead: model.googleCalendar.meetingLookAheadDays)
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: model.calendarEvents) { event -> Date in
            switch mode {
            case .day:
                return calendar.startOfDay(for: event.startDate)
            case .month:
                let components = calendar.dateComponents([.year, .month], from: event.startDate)
                return calendar.date(from: components) ?? calendar.startOfDay(for: event.startDate)
            case .year:
                let components = calendar.dateComponents([.year], from: event.startDate)
                return calendar.date(from: components) ?? calendar.startOfDay(for: event.startDate)
            }
        }
        return grouped
            .map { key, events in
                MeetingGroup(
                    id: key,
                    title: Self.title(for: key, mode: mode),
                    events: events.sorted { $0.startDate < $1.startDate },
                )
            }
            .sorted { $0.id < $1.id }
    }

    private static func title(for date: Date, mode: MeetingGroupMode) -> String {
        switch mode {
        case .day:
            return date.formatted(date: .complete, time: .omitted)
        case .month:
            return date.formatted(.dateTime.month(.wide).year())
        case .year:
            return date.formatted(.dateTime.year())
        }
    }
}


private struct MeetingCalendarHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Meeting calendar", systemImage: "video")
                    .font(.headline)
                    .foregroundStyle(Color.leaveInk)
                Spacer(minLength: 8)
                GlassControlGroup(spacing: 8) {
                    // Creating is the positive action here, so it carries the accent; refresh stays neutral.
                    Button {
                        model.beginNewMeeting()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.liquidGlassTinted(.leaveAccent))
                    .controlSize(.small)
                    .disabled(!model.isGoogleCalendarConnected)
                    .help(model.isGoogleCalendarConnected ? "New meeting (⇧⌘N)" : "Connect Google Calendar in Settings to create meetings")
                    .accessibilityLabel("Create a Google Calendar meeting")

                    // The spinner replaces the icon in place, so the header doesn't shift while refreshing.
                    Button {
                        Task { await model.refreshCalendarEvents() }
                    } label: {
                        if model.isRefreshingCalendar {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.liquidGlass)
                    .controlSize(.small)
                    .disabled(!model.isGoogleCalendarConnected || model.isRefreshingCalendar)
                    .help(refreshHelp)
                    .accessibilityLabel("Refresh Google Calendar meetings")
                }
            }

            Text(calendarSubtitle)
                .font(.subheadline)
                .foregroundStyle(Color.leaveMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var refreshHelp: String {
        if !model.isGoogleCalendarConnected {
            return "Connect Google Calendar in Settings to refresh meetings"
        }
        return model.isRefreshingCalendar ? "Refreshing meetings…" : "Refresh meetings"
    }

    private var calendarSubtitle: String {
        if model.isGoogleCalendarConnected {
            let mode = MeetingGroupMode(daysAhead: model.googleCalendar.meetingLookAheadDays).title
            let refreshed = model.calendarLastRefreshDate.map { " Last refreshed \($0.formatted(.relative(presentation: .named)))." } ?? ""
            return "Primary calendar for \(model.googleCalendarOwnerLabel), looking ahead \(model.googleCalendar.meetingLookAheadDays) days and grouped by \(mode). Live refresh every \(model.googleCalendar.liveRefreshIntervalSeconds) seconds.\(refreshed)"
        }
        return "Connect the Gmail owner's Google Calendar to see meetings that shape today's availability."
    }
}


private struct MeetingCancelledBanner: View {
    let cancelledCount: Int

    var body: some View {
        if cancelledCount > 0 {
            Label("\(cancelledCount) cancelled meeting\(cancelledCount == 1 ? "" : "s") found in this window", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.leaveOrange)
                .callout(.leaveOrange)
                .leaveTransition()
        }
    }
}


private struct MeetingCalendarContent: View {
    @EnvironmentObject private var model: AppModel

    let groups: [MeetingGroup]

    var body: some View {
        if !model.isGoogleCalendarConnected {
            MeetingEmptyState(
                icon: "calendar.badge.plus",
                title: "Connect Google Calendar in Settings",
                detail: "Meetings from the Gmail owner's primary calendar will appear here after OAuth is connected.",
                color: .leaveOrange,
            )
        } else if model.calendarEvents.isEmpty, model.isRefreshingCalendar {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading meetings...")
                    .font(.subheadline)
                    .foregroundStyle(Color.leaveMuted)
            }
            .padding(.vertical, 8)
        } else if model.calendarEvents.isEmpty {
            MeetingEmptyState(
                icon: "checkmark.circle",
                title: "No upcoming meetings",
                detail: "Your primary calendar is clear for this look-ahead window.",
                color: .leaveSuccess,
            )
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(groups) { group in
                    MeetingGroupSection(group: group)
                }
            }
        }
    }
}


private struct MeetingEmptyState: View {
    let icon: String
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(color)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Color.leaveMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}


private struct MeetingGroupSection: View {
    let group: MeetingGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.leaveMuted)

            VStack(spacing: 8) {
                ForEach(group.events) { event in
                    MeetingRow(event: event)
                        .leaveTransition()
                }
            }
        }
    }
}


private struct MeetingRow: View {
    let event: GoogleCalendarEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(systemName: icon, color: statusColor, size: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(event.isCancelled ? Color.leaveMuted : Color.leaveInk)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        Text("\(event.timeRangeText) ·")
                            .fixedSize(horizontal: false, vertical: true)
                        MeetingAttendeesButton(event: event)
                    }
                    .font(.caption)
                    .foregroundStyle(Color.leaveMuted)
                    if let location = event.location, !location.isEmpty {
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(Color.leaveMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if let meetingLink = event.meetingLink, !event.isCancelled {
                    // Joining is the row's key action, so it carries the accent; other row buttons stay neutral.
                    Link(destination: meetingLink) {
                        Image(systemName: "arrow.up.right")
                    }
                    .buttonStyle(.liquidGlassTinted(.leaveAccent))
                    .controlSize(.small)
                    .disabled(event.hasEnded)
                    .help(event.hasEnded ? "This meeting has ended" : "Join meeting")
                    .accessibilityLabel("Join \(event.title)")
                }
            }

            if event.isCancelled {
                Text("Cancelled")
                    .font(.caption.weight(.semibold))
                    .statusChip(.leaveOrange)
            } else {
                MeetingResponseControls(event: event)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .leaveRow(accent: statusColor)
        // `.contain` keeps the attendee, join, and RSVP buttons individually reachable.
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        if event.isCancelled {
            return "xmark.circle.fill"
        }
        return event.isAllDay ? "calendar" : "video.fill"
    }

    private var statusColor: Color {
        event.isCancelled ? .leaveOrange : .leaveAccent
    }

}


private struct MeetingResponseControls: View {
    @EnvironmentObject private var model: AppModel

    let event: GoogleCalendarEvent

    var body: some View {
        HStack(spacing: 8) {
            replyStatus

            Spacer(minLength: 8)

            GlassControlGroup(spacing: 6) {
                ForEach([CalendarResponseStatus.accepted, .tentative, .declined]) { response in
                    responseButton(response)
                }
            }
            .disabled(!canReply)
        }
        .leaveAnimation(LeaveMotion.quick, value: event.selfResponseStatus)
        .leaveAnimation(LeaveMotion.quick, value: isSending)
    }

    private var isSending: Bool {
        model.respondingEventIDs.contains(event.id)
    }

    /// Replies are blocked while one is being sent and for meetings you weren't invited to.
    private var canReply: Bool {
        event.canRespond && !isSending
    }

    @ViewBuilder
    private var replyStatus: some View {
        if isSending {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Sending reply…")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.leaveMuted)
        } else if event.canRespond {
            Label(event.selfResponseStatus.title, systemImage: event.selfResponseStatus.icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(event.selfResponseStatus.tint)
        } else {
            Label("No reply needed", systemImage: "person.crop.circle.badge.checkmark")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.leaveMuted)
        }
    }

    /// Every answer keeps its own color (with a distinct symbol, so color is never the only cue).
    /// The current answer is selected, not disabled: a disabled reply looked unavailable.
    private func responseButton(_ response: CalendarResponseStatus) -> some View {
        let isCurrent = event.canRespond && event.selfResponseStatus == response
        return Button {
            guard !isCurrent else {
                return
            }
            Task { await model.respondToMeeting(event, with: response) }
        } label: {
            Image(systemName: response.icon)
                .symbolVariant(isCurrent ? .fill : .none)
                .leaveSymbolBounce(value: isCurrent)
        }
        .buttonStyle(isCurrent ? .liquidGlassSelected(response.tint) : .liquidGlassTinted(response.tint))
        .controlSize(.small)
        .help(responseHelp(for: response, isCurrent: isCurrent))
        .accessibilityLabel("\(response.title) \(event.title)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func responseHelp(for response: CalendarResponseStatus, isCurrent: Bool) -> String {
        if !event.canRespond {
            return "Only invited guests can reply to this meeting"
        }
        if isSending {
            return "Sending your reply…"
        }
        return isCurrent ? "Your reply: \(response.title)" : "Reply \(response.title)"
    }
}


private struct LeaveListCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Label("Upcoming leave", systemImage: "calendar")
                        .font(.headline)
                        .foregroundStyle(Color.leaveInk)
                    Spacer(minLength: 8)
                    if model.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let report = model.latestReport {
            if report.leaves.isEmpty {
                emptyState
            } else {
                VStack(spacing: 8) {
                    ForEach(report.leaves) { leave in
                        leaveRow(leave, today: report.today)
                            .leaveTransition()
                    }
                }
                .leaveAnimation(value: report.leaves.map(\.id))
            }
        } else if model.isRefreshing {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading leave…")
                    .font(.subheadline)
                    .foregroundStyle(Color.leaveMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } else {
            Text("Your leave list will appear here. Use the refresh button to load it.")
                .font(.subheadline)
                .foregroundStyle(Color.leaveMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("No upcoming leave", systemImage: "checkmark.circle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.leaveSuccess)
            Text("No monitored employee starts approved leave in the next \(model.daysAhead) days.")
                .font(.caption)
                .foregroundStyle(Color.leaveMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func leaveRow(_ leave: LeaveSummary, today: Date) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(leave.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.leaveInk)
                Text("\(leave.leaveTypeWithPeriod) · \(leave.dateText()) · \(leave.accountEmail)")
                    .font(.caption)
                    .foregroundStyle(Color.leaveMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            daysLeftBadge(leave, today: today)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .leaveRow(accent: urgencyColor(leave, today: today))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(leave.name), \(leave.leaveTypeWithPeriod), \(leave.dateText()), \(leave.accountEmail), \(leave.remainingDaysLabel(from: today))")
    }

    private func daysLeftBadge(_ leave: LeaveSummary, today: Date) -> some View {
        Text(leave.remainingDaysLabel(from: today))
            .font(.caption.weight(.semibold))
            .statusChip(urgencyColor(leave, today: today))
            .fixedSize()
    }

    /// Orange once the leave has started, the accent color while it is still upcoming.
    private func urgencyColor(_ leave: LeaveSummary, today: Date) -> Color {
        let daysUntilStart = Calendar.current.dateComponents(
            [.day],
            from: today,
            to: Calendar.current.startOfDay(for: leave.startDate),
        ).day ?? 0
        return daysUntilStart <= 0 ? .leaveOrange : .leaveAccent
    }
}


private struct OnDemandChecksCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("On-demand checks")
                        .font(.headline)
                        .foregroundStyle(Color.leaveInk)
                    Text("Run a one-off check that sends notifications, or confirm your notification delivery.")
                        .font(.subheadline)
                        .foregroundStyle(Color.leaveMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button {
                        Task {
                            await model.checkNow()
                        }
                    } label: {
                        Label(model.isChecking ? "Checking…" : "Check now", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.liquidGlassProminent)
                    .disabled(model.isChecking)

                    Button {
                        Task {
                            await model.testNotification()
                        }
                    } label: {
                        Label("Test notification", systemImage: "bell.badge")
                    }
                    .buttonStyle(.liquidGlass)
                    .disabled(model.notificationPermission != .authorized)
                }
            }
        }
    }
}


private struct AccountCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var isConfirmingRemoval = false

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Label("Kakitangan accounts", systemImage: "person.crop.circle")
                        .font(.headline)
                        .foregroundStyle(Color.leaveInk)
                    Spacer()
                    Text("\(model.configuredAccountCount)")
                        .font(.caption.weight(.semibold))
                        .statusChip(.leaveAccent)
                }

                Picker("Account", selection: Binding(
                    get: { model.selectedAccountID ?? model.accounts.first?.id },
                    set: { id in
                        if let id {
                            model.selectAccount(id: id)
                        }
                    },
                )) {
                    ForEach(model.accounts) { account in
                        Text(account.accountEmail.isEmpty ? "New account" : account.accountEmail)
                            .tag(Optional(account.id))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Selected Kakitangan account")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Login email")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.leaveInk)
                    TextField("Login email", text: Binding(
                        get: { model.selectedAccountEmail },
                        set: { model.updateSelectedAccountEmail($0) },
                    ), prompt: .leavePrompt("name@g2g.com"))
                        .leaveInputField()
                        .accessibilityLabel("Kakitangan login email")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Password")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.leaveInk)
                    SecureField("Password", text: Binding(
                        get: { model.selectedAccount?.password ?? "" },
                        set: { model.updateSelectedPassword($0) },
                    ), prompt: .leavePrompt("Kakitangan password"))
                        .leaveInputField()
                        .accessibilityLabel("Kakitangan password")
                    Text("Leave the password blank to keep the one already saved in Keychain.")
                        .font(.caption)
                        .foregroundStyle(Color.leaveMuted)
                }

                HStack(spacing: 10) {
                    Button {
                        model.addAccount()
                    } label: {
                        Label("Add account", systemImage: "plus")
                    }
                    .buttonStyle(.liquidGlass)

                    Button(role: .destructive) {
                        isConfirmingRemoval = true
                    } label: {
                        Label("Remove account", systemImage: "trash")
                    }
                    .buttonStyle(.liquidGlass)
                    .disabled(model.accounts.count <= 1)
                    .confirmationDialog(
                        "Remove \(removalAccountName)?",
                        isPresented: $isConfirmingRemoval,
                    ) {
                        Button("Remove account", role: .destructive) {
                            model.removeSelectedAccount()
                        }
                    } message: {
                        Text("This account and its monitored people stop being checked once you save.")
                    }
                }
            }
        }
    }
}


extension AccountCard {
    fileprivate var removalAccountName: String {
        let email = model.selectedAccountEmail
        return email.isEmpty ? "this account" : email
    }
}


private struct MonitoredEmailsCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""
    @State private var newEmail = ""

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                header
                pickerControls
                pickerContent
                Divider()
                selectedUsersList
                Divider()
                manualFallback
                Divider()
                Stepper("Look ahead: \(model.daysAhead) days", value: $model.daysAhead, in: 0...365)
                    .accessibilityLabel("Look-ahead window in days")
            }
        }
        .task { await model.loadManagedEmployeesIfNeeded() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("People to monitor", systemImage: "person.2")
                    .font(.headline)
                    .foregroundStyle(Color.leaveInk)
                Spacer()
                Text("\(model.selectedAccountMonitoredEmployeeCount) selected")
                    .font(.caption)
                    .foregroundStyle(Color.leaveMuted)
            }
            Text("Select the employees to watch. Only approved leave active within the look-ahead window is included.")
                .font(.subheadline)
                .foregroundStyle(Color.leaveMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pickerControls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.leaveMuted)
                TextField("Search", text: $searchText, prompt: .leavePrompt("Search name or email"))
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .leaveRow()

            Button {
                Task { await model.loadManagedEmployees() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.liquidGlass)
            .disabled(model.isLoadingEmployees)
        }
    }

    @ViewBuilder
    private var pickerContent: some View {
        if model.isLoadingEmployees && (model.selectedAccount?.managedEmployees.isEmpty ?? true) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading employees…").foregroundStyle(Color.leaveMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } else if let error = model.selectedAccount?.employeeLoadError, model.selectedAccount?.managedEmployees.isEmpty ?? true {
            errorState(error)
        } else if model.selectedAccount?.managedEmployees.isEmpty ?? true {
            emptyState("No managed employees found.")
        } else {
            let groups = model.employeesByDepartment(matching: searchText)
            if groups.isEmpty {
                emptyState("No employees match your search.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups, id: \.department) { group in
                            Section {
                                ForEach(group.employees) { employee in
                                    employeeRow(employee)
                                }
                            } header: {
                                Text(group.department.uppercased())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.leaveMuted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    // Opaque so rows scrolling under the pinned header stay hidden.
                                    .background(Color.leaveSurface)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
    }

    private func employeeRow(_ employee: ManagedEmployee) -> some View {
        let selected = model.isMonitored(employee.email)
        return Button {
            model.setMonitored(employee.email, !selected)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? Color.leaveAccent : Color.leaveMuted)
                    .leaveSymbolBounce(value: selected)
                VStack(alignment: .leading, spacing: 1) {
                    Text(employee.displayName)
                        .foregroundStyle(Color.leaveInk)
                    Text(employee.email)
                        .font(.caption)
                        .foregroundStyle(Color.leaveMuted)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .leaveSelectableRow(isSelected: selected)
            .leaveHoverHighlight()
            .leaveAnimation(LeaveMotion.quick, value: selected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(employee.displayName), \(employee.email)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var manualFallback: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add by email")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.leaveInk)
            Text("Add someone who isn’t in your managed team.")
                .font(.caption)
                .foregroundStyle(Color.leaveMuted)

            HStack(spacing: 8) {
                TextField("Email", text: $newEmail, prompt: .leavePrompt("name@g2g.com"))
                    .leaveInputField()
                    .onSubmit(addManualEmail)
                    .accessibilityLabel("Add employee email manually")
                Button("Add", action: addManualEmail)
                    .buttonStyle(.liquidGlass)
                    .disabled(!newEmail.contains("@"))
            }
        }
    }

    private var selectedUsersList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Selected users", systemImage: "checklist")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.leaveInk)
                Spacer()
                Text("\(model.selectedAccountMonitoredEmployeeCount)")
                    .font(.caption.weight(.semibold))
                    .statusChip(.leaveAccent)
                    .accessibilityLabel("\(model.selectedAccountMonitoredEmployeeCount) selected users")
            }

            if model.selectedAccountMonitoredEmployeeCount == 0 {
                Text("No users selected yet.")
                    .font(.subheadline)
                    .foregroundStyle(Color.leaveMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(selectedManagedEmployees) { employee in
                            selectedManagedEmployeeRow(employee)
                                .leaveTransition()
                        }

                        ForEach(model.customMonitoredEmails, id: \.self) { email in
                            selectedEmailRow(email)
                                .leaveTransition()
                        }
                    }
                    .leaveAnimation(value: selectedManagedEmployees.map(\.id) + model.customMonitoredEmails)
                }
                .frame(maxHeight: 220)
            }
        }
    }

    private var selectedManagedEmployees: [ManagedEmployee] {
        (model.selectedAccount?.managedEmployees ?? [])
            .filter { model.isMonitored($0.email) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func selectedManagedEmployeeRow(_ employee: ManagedEmployee) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.leaveAccent)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(employee.displayName)
                    .foregroundStyle(Color.leaveInk)
                Text(employee.email)
                    .font(.caption)
                    .foregroundStyle(Color.leaveMuted)
            }

            Spacer(minLength: 8)

            // Deselecting is reversible, so it stays neutral; red is kept for actions that lose data.
            Button {
                model.setMonitored(employee.email, false)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.liquidGlass)
            .accessibilityLabel("Remove \(employee.displayName)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .leaveRow()
    }

    private func selectedEmailRow(_ email: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.leaveAccent)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(email)
                    .foregroundStyle(Color.leaveInk)
                Text("Added by email")
                    .font(.caption)
                    .foregroundStyle(Color.leaveMuted)
            }

            Spacer(minLength: 8)

            Button {
                model.setMonitored(email, false)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.liquidGlass)
            .accessibilityLabel("Remove \(email)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .leaveRow()
    }

    private func errorState(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.leaveOrange)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.leaveMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") {
                    Task { await model.loadManagedEmployees() }
                }
                .buttonStyle(.liquidGlass)
                .controlSize(.small)
            }
        }
        .callout(.leaveOrange)
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(Color.leaveMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private func addManualEmail() {
        let trimmed = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@") else {
            return
        }
        model.setMonitored(trimmed, true)
        newEmail = ""
    }
}


private struct GoogleCalendarCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var newReminderMinutes = 15
    @State private var isConfirmingDisconnect = false

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Google Calendar", systemImage: "calendar.badge.clock")
                        .font(.headline)
                        .foregroundStyle(Color.leaveInk)
                    Text("Connect the Gmail owner’s primary calendar and show meetings beside Kakitangan leave.")
                        .font(.subheadline)
                        .foregroundStyle(Color.leaveMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: model.googleCalendar.isConfigured ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.googleCalendar.isConfigured ? Color.leaveSuccess : Color.leaveOrange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.googleCalendar.isConfigured ? "Firebase and Google Sign-In are configured" : "Firebase needs configuration")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.leaveInk)
                        Text(clientIDDetail)
                            .font(.caption)
                            .foregroundStyle(Color.leaveMuted)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .callout(model.googleCalendar.isConfigured ? .leaveSuccess : .leaveOrange)

                Stepper(
                    "Meeting look ahead: \(model.googleCalendar.meetingLookAheadDays) days",
                    value: Binding(
                        get: { model.googleCalendar.meetingLookAheadDays },
                        set: { model.updateGoogleCalendarLookAheadDays($0) },
                    ),
                    in: 0...365,
                )
                .accessibilityLabel("Google Calendar meeting look-ahead window")

                Stepper(
                    "Live refresh: every \(model.googleCalendar.liveRefreshIntervalSeconds) seconds",
                    value: Binding(
                        get: { model.googleCalendar.liveRefreshIntervalSeconds },
                        set: { model.updateGoogleCalendarLiveRefreshInterval($0) },
                    ),
                    in: 15...3_600,
                    step: 15,
                )
                .accessibilityLabel("Google Calendar live refresh interval")

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Meeting reminders", systemImage: "bell.badge")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.leaveInk)
                        Spacer()
                        Text("\(model.googleCalendar.reminderLeadTimes.count)")
                            .font(.caption.weight(.semibold))
                            .statusChip(.leaveAccent)
                    }

                    if model.googleCalendar.reminderLeadTimes.isEmpty {
                        Text("No meeting reminders are scheduled.")
                            .font(.caption)
                            .foregroundStyle(Color.leaveMuted)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(model.googleCalendar.reminderLeadTimes.sorted()) { leadTime in
                                HStack(spacing: 10) {
                                    Image(systemName: "bell")
                                        .foregroundStyle(Color.leaveAccent)
                                        .frame(width: 20)
                                    Text(leadTime.label)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.leaveInk)
                                    Spacer()
                                    Button(role: .destructive) {
                                        model.removeMeetingReminder(id: leadTime.id)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.liquidGlass)
                                    .controlSize(.small)
                                    .accessibilityLabel("Remove \(leadTime.label)")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .leaveRow()
                                .leaveTransition()
                            }
                        }
                        .leaveAnimation(value: model.googleCalendar.reminderLeadTimes.sorted())
                    }

                    HStack(spacing: 8) {
                        Stepper(
                            "\(newReminderMinutes) minutes before",
                            value: $newReminderMinutes,
                            in: 0...43_200,
                            step: 5,
                        )
                        Button {
                            model.addMeetingReminder(minutes: newReminderMinutes)
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .buttonStyle(.liquidGlass)
                    }

                    HStack(spacing: 8) {
                        ForEach([5, 10, 15, 30, 60, 1_440], id: \.self) { minutes in
                            Button(MeetingReminderLeadTimeLabel.minutes(minutes)) {
                                newReminderMinutes = minutes
                                model.addMeetingReminder(minutes: minutes)
                            }
                            .buttonStyle(.liquidGlass)
                            .controlSize(.small)
                        }
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    Button {
                        Task { await model.connectGoogleCalendar() }
                    } label: {
                        Label(connectButtonTitle, systemImage: model.isGoogleCalendarConnected ? "arrow.triangle.2.circlepath" : "link")
                    }
                    .buttonStyle(.liquidGlassProminent)
                    .disabled(model.isConnectingGoogleCalendar || !model.googleCalendar.isConfigured)

                    Button(role: .destructive) {
                        isConfirmingDisconnect = true
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.liquidGlass)
                    .disabled(!model.isGoogleCalendarConnected)
                    .confirmationDialog(
                        "Disconnect Google Calendar?",
                        isPresented: $isConfirmingDisconnect,
                    ) {
                        Button("Disconnect", role: .destructive) {
                            model.disconnectGoogleCalendar()
                        }
                    } message: {
                        Text("Meetings and RSVP replies stop until you sign in to Google again.")
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: model.isGoogleCalendarConnected ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(model.isGoogleCalendarConnected ? Color.leaveSuccess : Color.leaveOrange)
                    Text(connectionDetail)
                        .font(.caption)
                        .foregroundStyle(Color.leaveMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .callout(model.isGoogleCalendarConnected ? .leaveSuccess : .leaveOrange)
            }
        }
        // Connecting or disconnecting recolors the status callouts together.
        .leaveAnimation(value: model.isGoogleCalendarConnected)
    }

    private var connectButtonTitle: String {
        if model.isConnectingGoogleCalendar {
            return "Connecting…"
        }
        return model.isGoogleCalendarConnected ? "Reconnect Google" : "Connect Google"
    }

    private var clientIDDetail: String {
        if model.googleCalendar.isConfigured {
            return GoogleCalendarConfiguration.bundleClientID
        }
        return "Add GoogleService-Info.plist from the Firebase console to the app Resources folder."
    }

    private var connectionDetail: String {
        if model.isGoogleCalendarConnected {
            return "Connected as \(model.googleCalendarOwnerLabel). The app reads events, watches for changes while open, and can update your RSVP on the primary calendar."
        }
        return "Click Connect Google to sign in with the Google SDK. Reconnect if you previously granted read-only access so RSVP updates can be authorized."
    }
}


private enum MeetingReminderLeadTimeLabel {
    static func minutes(_ minutes: Int) -> String {
        switch minutes {
        case 0:
            return "Start"
        case 1..<60:
            return "\(minutes)m"
        case 60:
            return "1h"
        case 61..<1_440 where minutes % 60 == 0:
            return "\(minutes / 60)h"
        case 1_440:
            return "1d"
        case 1_441... where minutes % 1_440 == 0:
            return "\(minutes / 1_440)d"
        default:
            return "\(minutes)m"
        }
    }
}


private struct NotificationTimesCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Weekday check times", systemImage: "clock")
                            .font(.headline)
                            .foregroundStyle(Color.leaveInk)
                        Text("The app checks Kakitangan at every selected time, Monday through Friday.")
                            .font(.subheadline)
                            .foregroundStyle(Color.leaveMuted)
                    }
                    Spacer()
                }

                if model.notificationTimes.isEmpty {
                    Label("No weekday checks are scheduled.", systemImage: "calendar.badge.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(Color.leaveOrange)
                        .padding(.vertical, 10)
                } else {
                    VStack(spacing: 8) {
                        ForEach(model.notificationTimes) { notificationTime in
                            notificationTimeRow(notificationTime)
                                .leaveTransition()
                        }
                    }
                    .leaveAnimation(value: model.notificationTimes.map(\.id))
                }

                Button {
                    model.addNotificationTime()
                } label: {
                    Label("Add time", systemImage: "plus")
                }
                .buttonStyle(.liquidGlass)

                Divider()

                Toggle(isOn: $model.runAtLogin) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Check at sign-in")
                            .foregroundStyle(Color.leaveInk)
                        Text("Runs a hidden leave check after you sign in to this Mac.")
                            .font(.caption)
                            .foregroundStyle(Color.leaveMuted)
                    }
                }
                .toggleStyle(.switch)
                .accessibilityHint("Enables an automatic background check after you sign in to this Mac.")

                Text("Deleting the final time stops weekday checks. Turn off Check at sign-in too to disable every automatic check; Check now remains available.")
                    .font(.caption)
                    .foregroundStyle(Color.leaveMuted)
            }
        }
    }

    private func notificationTimeRow(_ notificationTime: NotificationTime) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bell")
                .foregroundStyle(Color.leaveAccent)
                .frame(width: 20)

            LeaveDateField(
                selection: Binding(
                    get: { model.date(for: notificationTime) },
                    set: { model.updateNotificationTime(id: notificationTime.id, to: $0) },
                ),
                accessibilityLabel: "Notification time",
            )
            .fixedSize()
            .leaveInputField()

            Spacer()

            Button(role: .destructive) {
                model.removeNotificationTime(id: notificationTime.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.liquidGlass)
            .accessibilityLabel("Delete \(model.date(for: notificationTime).formatted(date: .omitted, time: .shortened)) notification time")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .leaveRow()
    }
}


private struct LoginItemCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    IconTile(systemName: statusIcon, color: statusColor, size: 38)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Open app at login")
                            .font(.headline)
                            .foregroundStyle(Color.leaveInk)
                        Text(statusDetail)
                            .font(.subheadline)
                            .foregroundStyle(Color.leaveMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    Toggle(
                        "Open Kakitangan Companion at login",
                        isOn: Binding(
                            get: { model.isOpenAtLoginEnabled },
                            set: { model.setOpenAtLogin($0) },
                        ),
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!model.canConfigureOpenAtLogin)
                    .accessibilityLabel("Open Kakitangan Companion at login")
                    .accessibilityHint("Adds or removes this app from the Open at Login list in System Settings.")
                }

                HStack(spacing: 12) {
                    Button {
                        model.openLoginItemSettings()
                    } label: {
                        Label("Open Login Items", systemImage: "gearshape")
                    }
                    .buttonStyle(.liquidGlass)
                    .disabled(!model.canConfigureOpenAtLogin)

                    Button("Refresh status") {
                        model.refreshLoginItemStatus()
                    }
                    .buttonStyle(.liquidGlass)
                    .disabled(!model.canConfigureOpenAtLogin)
                }

                Text("This opens the app window after you sign in and appears in System Settings → General → Login Items. It is separate from Check at sign-in, which runs a hidden leave check.")
                    .font(.caption)
                    .foregroundStyle(Color.leaveMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusIcon: String {
        switch model.loginItemStatus {
        case .enabled:
            return "checkmark.circle.fill"
        case .disabled:
            return "power"
        case .requiresApproval:
            return "exclamationmark.circle.fill"
        case .unavailable:
            return "macwindow"
        case .notFound:
            return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch model.loginItemStatus {
        case .enabled:
            return .leaveSuccess
        case .disabled, .unavailable, .notFound:
            return .leaveOrange
        case .requiresApproval:
            return .leaveRed
        }
    }

    private var statusDetail: String {
        switch model.loginItemStatus {
        case .enabled:
            return "Kakitangan Companion appears in Open at Login and will open after you sign in."
        case .disabled:
            return "Turn this on to add Kakitangan Companion to Open at Login."
        case .requiresApproval:
            return "macOS needs your approval. Open Login Items and enable Kakitangan Companion."
        case .unavailable:
            return "Open at Login requires macOS 13 or later. Check at sign-in still works on this Mac."
        case .notFound:
            return "macOS could not find this app's login item. Try turning the switch on again."
        }
    }
}


private struct AppVisibilityCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("App visibility", systemImage: "macwindow")
                        .font(.headline)
                        .foregroundStyle(Color.leaveInk)
                    Text("Choose where Kakitangan Companion stays available while you work. The change applies now; save setup to keep it.")
                        .font(.subheadline)
                        .foregroundStyle(Color.leaveMuted)
                }

                Picker(
                    "Show Kakitangan Companion in",
                    selection: Binding(
                        get: { model.appVisibility },
                        set: { visibility in
                            DispatchQueue.main.async {
                                model.setAppVisibility(visibility)
                            }
                        },
                    ),
                ) {
                    Text("Menu Bar & Dock").tag(AppVisibility.menuBarAndDock)
                    Text("Menu Bar only").tag(AppVisibility.menuBarOnly)
                    Text("Dock only").tag(AppVisibility.dockOnly)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Show Kakitangan Companion in")
                .accessibilityHint("Choose whether the app appears in the Menu Bar, the Dock, or both.")

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: visibilityIcon)
                        .foregroundStyle(Color.leaveAccent)
                        .frame(width: 20)
                    Text(visibilityDetail)
                        .font(.caption)
                        .foregroundStyle(Color.leaveMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .callout(.leaveAccent)
            }
        }
    }

    private var visibilityIcon: String {
        switch model.appVisibility {
        case .menuBarAndDock:
            return "menubar.dock.rectangle"
        case .menuBarOnly:
            return "menubar.rectangle"
        case .dockOnly:
            return "dock.rectangle"
        }
    }

    private var visibilityDetail: String {
        switch model.appVisibility {
        case .menuBarAndDock:
            return "The menu-bar icon gives quick actions, and the Dock keeps the app easy to find."
        case .menuBarOnly:
            return "The Dock icon is hidden. Use the menu-bar icon to open Leave Watch, check now, or quit."
        case .dockOnly:
            return "The menu-bar icon is hidden. Open Kakitangan Companion from the Dock."
        }
    }
}


private struct UpdatesCard: View {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Software updates", systemImage: "arrow.down.circle")
                        .font(.headline)
                        .foregroundStyle(Color.leaveInk)
                    Text("Version \(Self.appVersion). Updates are downloaded from the secure Sparkle feed.")
                        .font(.subheadline)
                        .foregroundStyle(Color.leaveMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle(isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.setAutomaticallyChecksForUpdates($0) },
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Automatically check for updates")
                            .foregroundStyle(Color.leaveInk)
                        Text(lastCheckDescription)
                            .font(.caption)
                            .foregroundStyle(Color.leaveMuted)
                    }
                }
                .toggleStyle(.switch)
                .accessibilityHint("Lets Sparkle check for new versions in the background.")

                Button {
                    updater.checkForUpdates()
                } label: {
                    Label("Check for Updates…", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.liquidGlass)
                .disabled(!updater.canCheckForUpdates)
            }
        }
    }

    private var lastCheckDescription: String {
        guard let date = updater.lastUpdateCheckDate else {
            return "No update check has run yet."
        }
        return "Last checked \(date.formatted(.relative(presentation: .named)))."
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}


private struct PermissionCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SurfaceCard {
            HStack(alignment: .center, spacing: 16) {
                IconTile(systemName: permissionIcon, color: permissionColor, size: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text(permissionTitle)
                        .font(.headline)
                        .foregroundStyle(Color.leaveInk)
                    Text(permissionDetail)
                        .font(.subheadline)
                        .foregroundStyle(Color.leaveMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if model.notificationPermission == .notDetermined {
                    Button("Allow notifications") {
                        Task {
                            await model.requestNotificationPermission()
                        }
                    }
                    .buttonStyle(.liquidGlassProminent)
                    .disabled(model.isRequestingPermission)
                }
            }
        }
    }

    private var permissionIcon: String {
        switch model.notificationPermission {
        case .authorized:
            return "bell.badge.fill"
        case .notDetermined:
            return "bell"
        case .denied, .unsupported:
            return "bell.slash"
        }
    }

    private var permissionColor: Color {
        switch model.notificationPermission {
        case .authorized:
            return .leaveSuccess
        case .notDetermined:
            return .leaveOrange
        case .denied, .unsupported:
            return .leaveRed
        }
    }

    private var permissionTitle: String {
        switch model.notificationPermission {
        case .authorized:
            return "Notifications are enabled"
        case .notDetermined:
            return "Allow leave alerts"
        case .denied:
            return "Notifications need attention"
        case .unsupported:
            return "macOS 12 or later is required"
        }
    }

    private var permissionDetail: String {
        switch model.notificationPermission {
        case .authorized:
            return "For urgent leave alerts, choose Time Sensitive and Persistent alerts in System Settings → Notifications."
        case .notDetermined:
            return "You control when alerts appear. The prompt opens only after you choose Allow notifications."
        case .denied:
            return "Enable notifications, Time Sensitive alerts, and Persistent alert style in System Settings → Notifications → Kakitangan Companion."
        case .unsupported:
            return "Update this Mac before enabling leave notifications."
        }
    }
}


private struct MetricCard: View {
    @EnvironmentObject private var model: AppModel

    let title: String
    let value: String
    let icon: String
    /// Status color for the icon, so metrics that need attention stand out from the rest.
    var tint: Color = .leaveAccent
    /// Where clicking the card goes: the tab or settings section that owns this metric.
    let destination: DashboardRequest

    var body: some View {
        Button {
            model.handle(destination)
        } label: {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        IconTile(systemName: icon, color: tint, size: 30)
                        Text(title.uppercased())
                            .font(.caption.weight(.semibold))
                            .tracking(0.8)
                            .foregroundStyle(Color.leaveMuted)
                        Spacer(minLength: 4)
                        CardChevron()
                    }
                    // No text selection here: the whole card is a button.
                    Text(value)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.leaveInk)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .leaveNumericTransition()
                }
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            }
        }
        .buttonStyle(.leaveCard)
        .help("Open \(destination.title)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityHint("Opens \(destination.title)")
        // Counts roll to their new value after a refresh instead of jumping.
        .leaveAnimation(value: value)
    }
}


private struct StatusMessage: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "info.circle.fill")
            .font(.subheadline)
            .foregroundStyle(Color.leaveInk)
            .callout(.leaveAccent)
    }
}


/// Solid brand tile. It anchors the header, so it is filled rather than glass or tinted.
private struct AppMark: View {
    var body: some View {
        Image(systemName: "calendar.badge.clock")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(
                LinearGradient(
                    colors: [Color.leaveAccentFill, Color.leaveAccentFill.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing,
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous),
            )
            .shadow(color: Color.leaveShadow, radius: 6, y: 2)
            .accessibilityHidden(true)
    }
}
