import AppKit
import SwiftUI


struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.leaveCanvas
                .ignoresSafeArea()

            switch model.screen {
            case .setup, .editing:
                SettingsView(isEditing: model.isEditing)
            case .dashboard:
                GeometryReader { proxy in
                    ScrollView {
                        DashboardView(width: proxy.size.width)
                            .padding(proxy.size.width < 640 ? 16 : 32)
                            .frame(maxWidth: 1120, alignment: .topLeading)
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.86),
            value: model.screen,
        )
        .task {
            await model.refreshNotificationPermission()
        }
    }
}


private struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    let isEditing: Bool

    @State private var selectedSection: SettingsSection = .account

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 18)

            TabView(selection: $selectedSection) {
                settingsTab {
                    AccountCard()
                    MonitoredEmailsCard()
                }
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(SettingsSection.account)

                settingsTab {
                    GoogleCalendarCard()
                }
                .tabItem { Label("Calendar", systemImage: "calendar.badge.clock") }
                .tag(SettingsSection.calendar)

                settingsTab {
                    PermissionCard()
                    NotificationTimesCard()
                    OnDemandChecksCard()
                }
                .tabItem { Label("Notifications", systemImage: "bell") }
                .tag(SettingsSection.notifications)

                settingsTab {
                    LoginItemCard()
                    AppVisibilityCard()
                    UpdatesCard()
                }
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsSection.general)
            }
            // The AppKit tab strip measures its segment labels mid-animation and
            // collapses them until clicked, so keep the screen-switch spring out of it.
            .animation(nil, value: model.screen)
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
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.statusMessage.isEmpty {
                StatusMessage(message: model.statusMessage)
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
                .tint(.leaveTeal)
                .controlSize(.large)

                Spacer(minLength: 0)
            }

            Text("Your password is saved only in the macOS Keychain. This app never displays or exports it.")
                .font(.caption)
                .foregroundStyle(Color.leaveMuted)
        }
    }
}


private enum SettingsSection: Hashable {
    case account
    case calendar
    case notifications
    case general
}


private enum DashboardSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case meetings = "Meetings"
    case leave = "Leave"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "rectangle.grid.2x2"
        case .meetings: return "video"
        case .leave: return "calendar"
        }
    }
}


private struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    let width: CGFloat

    @State private var selectedSection: DashboardSection = .overview

    private var isCompact: Bool {
        width < 720
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            DashboardHeader(isCompact: isCompact)

            TabView(selection: $selectedSection) {
                DashboardOverview(isCompact: isCompact)
                    .padding(20)
                    .tabItem { Label(DashboardSection.overview.rawValue, systemImage: DashboardSection.overview.icon) }
                    .tag(DashboardSection.overview)

                MeetingCalendarCard()
                    .padding(20)
                    .tabItem { Label(DashboardSection.meetings.rawValue, systemImage: DashboardSection.meetings.icon) }
                    .tag(DashboardSection.meetings)

                LeaveListCard()
                    .padding(20)
                    .tabItem { Label(DashboardSection.leave.rawValue, systemImage: DashboardSection.leave.icon) }
                    .tag(DashboardSection.leave)
            }
            // See SettingsView: keep the screen-switch spring out of the AppKit tab strip.
            .animation(nil, value: model.screen)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            if !model.statusMessage.isEmpty {
                StatusMessage(message: model.statusMessage)
            }
        }
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
        HStack(spacing: 10) {
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
                MetricCard(title: "Accounts", value: "\(model.configuredAccountCount)", icon: "person.crop.circle")
                MetricCard(title: "Watching", value: "\(model.monitoredEmployeeCount) people", icon: "person.2")
                MetricCard(title: "Leave horizon", value: "\(model.daysAhead) days", icon: "calendar")
                MetricCard(
                    title: "Meetings",
                    value: model.isGoogleCalendarConnected ? "\(model.upcomingMeetingCount) upcoming" : "Not connected",
                    icon: "video",
                )
                MetricCard(
                    title: "Cancelled",
                    value: model.cancelledMeetingCount == 0 ? "None" : "\(model.cancelledMeetingCount) meetings",
                    icon: "xmark.circle",
                )
                MetricCard(title: "Reminders", value: model.meetingReminderSummary, icon: "bell.badge")
            }
        }
    }
}


private struct ScheduleStatusCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SurfaceCard {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: scheduleIcon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(scheduleColor)
                    .frame(width: 46, height: 46)
                    .liquidGlassSurface(cornerRadius: 14, tint: scheduleColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(scheduleTitle)
                        .font(.headline)
                        .foregroundStyle(Color.leaveInk)
                    Text(scheduleDescription)
                        .font(.subheadline)
                        .foregroundStyle(Color.leaveMuted)
                }

                Spacer(minLength: 12)

                Button(scheduleButtonTitle) {
                    model.installWeekdaySchedule()
                }
                .buttonStyle(.liquidGlassProminent)
                .tint(.leaveTeal)
                .disabled(model.isInstallingSchedule || !model.hasAutomatedCheck)
            }
        }
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
        model.isWeekdayScheduleInstalled && !model.needsScheduleRefresh ? .leaveTeal : .leaveOrange
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
                if model.isRefreshingCalendar {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    Task { await model.refreshCalendarEvents() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.liquidGlass)
                .controlSize(.small)
                .disabled(!model.isGoogleCalendarConnected || model.isRefreshingCalendar)
                .help("Refresh meetings")
                .accessibilityLabel("Refresh Google Calendar meetings")
            }

            Text(calendarSubtitle)
                .font(.subheadline)
                .foregroundStyle(Color.leaveMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlassSurface(cornerRadius: 10, tint: .leaveOrange)
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
                color: .leaveTeal,
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
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 26, height: 26)
                    .liquidGlassSurface(cornerRadius: 8, tint: statusColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(event.isCancelled ? Color.leaveMuted : Color.leaveInk)
                        .lineLimit(2)
                    Text("\(event.timeRangeText) · \(event.participantCountText)")
                        .font(.caption)
                        .foregroundStyle(Color.leaveMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let location = event.location, !location.isEmpty {
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(Color.leaveMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if let meetingLink = event.meetingLink, !event.isCancelled {
                    Link(destination: meetingLink) {
                        Image(systemName: "arrow.up.right")
                    }
                    .buttonStyle(.liquidGlass)
                    .controlSize(.small)
                    .accessibilityLabel("Open \(event.title)")
                }
            }

            if event.isCancelled {
                Text("Cancelled")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.leaveOrange)
            } else {
                MeetingResponseControls(event: event)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .liquidGlassSurface(cornerRadius: 12, tint: statusColor, interactive: true)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        if event.isCancelled {
            return "xmark.circle.fill"
        }
        return event.isAllDay ? "calendar" : "video.fill"
    }

    private var statusColor: Color {
        event.isCancelled ? .leaveOrange : .leaveTeal
    }

}


private struct MeetingResponseControls: View {
    @EnvironmentObject private var model: AppModel

    let event: GoogleCalendarEvent

    var body: some View {
        HStack(spacing: 8) {
            Label(event.selfResponseStatus.title, systemImage: event.selfResponseStatus.icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.leaveMuted)

            Spacer(minLength: 8)

            ForEach([CalendarResponseStatus.accepted, .tentative, .declined]) { response in
                Button {
                    Task { await model.respondToMeeting(event, with: response) }
                } label: {
                    Image(systemName: response.icon)
                }
                .buttonStyle(.liquidGlass)
                .controlSize(.small)
                .disabled(event.selfResponseStatus == response)
                .help(response.title)
                .accessibilityLabel("\(response.title) \(event.title)")
            }
        }
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
                    }
                }
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
                .foregroundStyle(Color.leaveTeal)
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
                Text("\(leave.leaveTypeWithPeriod) · \(dateText(leave)) · \(leave.accountEmail)")
                    .font(.caption)
                    .foregroundStyle(Color.leaveMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            daysLeftBadge(leave, today: today)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .liquidGlassSurface(cornerRadius: 12, tint: .leaveTeal, interactive: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(leave.name), \(leave.leaveTypeWithPeriod), \(dateText(leave)), \(leave.accountEmail), \(leave.remainingDaysLabel(from: today))")
    }

    private func daysLeftBadge(_ leave: LeaveSummary, today: Date) -> some View {
        let daysUntilStart = Calendar.current.dateComponents(
            [.day],
            from: today,
            to: Calendar.current.startOfDay(for: leave.startDate),
        ).day ?? 0
        let color: Color = daysUntilStart <= 0 ? .leaveOrange : .leaveTeal

        return Text(leave.remainingDaysLabel(from: today))
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .liquidGlassCapsule(tint: color)
            .fixedSize()
    }

    private func dateText(_ leave: LeaveSummary) -> String {
        let calendar = Calendar.current
        if calendar.isDate(leave.startDate, inSameDayAs: leave.endDate) {
            return DateOnly.display(leave.startDate)
        }
        let days = (calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: leave.startDate),
            to: calendar.startOfDay(for: leave.endDate),
        ).day ?? 0) + 1
        return "\(DateOnly.display(leave.startDate)) – \(DateOnly.display(leave.endDate)) (\(days) days)"
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
                    .tint(.leaveTeal)
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
                        .foregroundStyle(Color.leaveTeal)
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
                    TextField("name@g2g.com", text: Binding(
                        get: { model.selectedAccountEmail },
                        set: { model.updateSelectedAccountEmail($0) },
                    ))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Kakitangan login email")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Password")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.leaveInk)
                    SecureField("Kakitangan password", text: Binding(
                        get: { model.selectedAccount?.password ?? "" },
                        set: { model.updateSelectedPassword($0) },
                    ))
                        .textFieldStyle(.roundedBorder)
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
                        model.removeSelectedAccount()
                    } label: {
                        Label("Remove account", systemImage: "trash")
                    }
                    .buttonStyle(.liquidGlass)
                    .disabled(model.accounts.count <= 1)
                }
            }
        }
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
                TextField("Search name or email", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .liquidGlassSurface(cornerRadius: 10, tint: .leaveTeal, interactive: true)

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
                                    .liquidGlassSurface(cornerRadius: 8)
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
                    .foregroundStyle(selected ? Color.leaveTeal : Color.leaveMuted)
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
            .liquidGlassSurface(cornerRadius: 10, tint: selected ? .leaveTeal : nil, interactive: true)
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
                TextField("name@g2g.com", text: $newEmail)
                    .textFieldStyle(.roundedBorder)
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
                    .foregroundStyle(Color.leaveTeal)
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
                        }

                        ForEach(model.customMonitoredEmails, id: \.self) { email in
                            selectedEmailRow(email)
                        }
                    }
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
                .foregroundStyle(Color.leaveTeal)
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

            Button(role: .destructive) {
                model.setMonitored(employee.email, false)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.liquidGlass)
            .accessibilityLabel("Remove \(employee.displayName)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlassSurface(cornerRadius: 12, tint: .leaveTeal, interactive: true)
    }

    private func selectedEmailRow(_ email: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.leaveTeal)
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

            Button(role: .destructive) {
                model.setMonitored(email, false)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.liquidGlass)
            .accessibilityLabel("Remove \(email)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlassSurface(cornerRadius: 12, tint: .leaveTeal, interactive: true)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .liquidGlassSurface(cornerRadius: 10, tint: .leaveTeal, interactive: true)
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
                        .foregroundStyle(model.googleCalendar.isConfigured ? Color.leaveTeal : Color.leaveOrange)
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
                .padding(12)
                .liquidGlassSurface(cornerRadius: 12, tint: .leaveTeal, interactive: true)

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

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Meeting reminders", systemImage: "bell.badge")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.leaveInk)
                        Spacer()
                        Text("\(model.googleCalendar.reminderLeadTimes.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.leaveTeal)
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
                                        .foregroundStyle(Color.leaveTeal)
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
                                .liquidGlassSurface(cornerRadius: 12, tint: .leaveTeal, interactive: true)
                            }
                        }
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
                .padding(12)
                .liquidGlassSurface(cornerRadius: 12, tint: .leaveTeal, interactive: true)

                HStack(spacing: 12) {
                    Button {
                        Task { await model.connectGoogleCalendar() }
                    } label: {
                        Label(connectButtonTitle, systemImage: model.isGoogleCalendarConnected ? "arrow.triangle.2.circlepath" : "link")
                    }
                    .buttonStyle(.liquidGlassProminent)
                    .tint(.leaveTeal)
                    .disabled(model.isConnectingGoogleCalendar || !model.googleCalendar.isConfigured)

                    Button(role: .destructive) {
                        model.disconnectGoogleCalendar()
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.liquidGlass)
                    .disabled(!model.isGoogleCalendarConnected)
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: model.isGoogleCalendarConnected ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(model.isGoogleCalendarConnected ? Color.leaveTeal : Color.leaveOrange)
                    Text(connectionDetail)
                        .font(.caption)
                        .foregroundStyle(Color.leaveMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .liquidGlassSurface(cornerRadius: 12, tint: .leaveTeal, interactive: true)
            }
        }
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
                        }
                    }
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
                .foregroundStyle(Color.leaveTeal)
                .frame(width: 20)

            DatePicker(
                "Notification time",
                selection: Binding(
                    get: { model.date(for: notificationTime) },
                    set: { model.updateNotificationTime(id: notificationTime.id, to: $0) },
                ),
                displayedComponents: .hourAndMinute,
            )
            .labelsHidden()
            .datePickerStyle(.field)
            .accessibilityLabel("Notification time")

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
        .liquidGlassSurface(cornerRadius: 12, tint: .leaveTeal, interactive: true)
    }
}


private struct LoginItemCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .frame(width: 30, height: 30)
                        .background(
                            statusColor.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous),
                        )

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
            return .leaveTeal
        case .disabled, .unavailable, .notFound:
            return .leaveOrange
        case .requiresApproval:
            return .red
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
                        .foregroundStyle(Color.leaveTeal)
                        .frame(width: 20)
                    Text(visibilityDetail)
                        .font(.caption)
                        .foregroundStyle(Color.leaveMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .liquidGlassSurface(cornerRadius: 12, tint: .leaveTeal, interactive: true)
            }
        }
    }

    private var visibilityIcon: String {
        switch model.appVisibility {
        case .menuBarAndDock:
            return "macwindow"
        case .menuBarOnly:
            return "macwindow"
        case .dockOnly:
            return "macwindow"
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
                Image(systemName: permissionIcon)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(permissionColor)
                    .frame(width: 46, height: 46)
                    .background(permissionColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

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
                    .tint(.leaveTeal)
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
            return .leaveTeal
        case .notDetermined:
            return .leaveOrange
        case .denied, .unsupported:
            return .red
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
    let title: String
    let value: String
    let icon: String

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 15) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.leaveTeal)
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.leaveMuted)
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.leaveInk)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        }
    }
}


private struct StatusMessage: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "info.circle")
            .font(.subheadline)
            .foregroundStyle(Color.leaveInk)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassSurface(cornerRadius: 14, tint: .leaveTeal)
    }
}


private struct SurfaceCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassSurface(cornerRadius: 22)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.leaveTeal.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 8)
    }
}


private struct AppMark: View {
    var body: some View {
        Image(systemName: "calendar.badge.clock")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(Color.leaveInk)
            .frame(width: 48, height: 48)
            .liquidGlassSurface(cornerRadius: 16, tint: .leaveTeal, interactive: true)
            .accessibilityHidden(true)
    }
}


private struct LiquidGlassButtonStyle: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(isProminent ? .semibold : .regular))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .foregroundStyle(Color.leaveInk)
            .liquidGlassSurface(
                cornerRadius: 9,
                tint: isProminent ? .leaveTeal : nil,
                interactive: true,
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}


private extension ButtonStyle where Self == LiquidGlassButtonStyle {
    static var liquidGlass: LiquidGlassButtonStyle {
        LiquidGlassButtonStyle(isProminent: false)
    }

    static var liquidGlassProminent: LiquidGlassButtonStyle {
        LiquidGlassButtonStyle(isProminent: true)
    }
}


private extension View {
    @ViewBuilder
    func liquidGlassSurface(cornerRadius: CGFloat, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let resolvedTint = tint ?? Color.leaveTeal
        if #available(macOS 26.0, *) {
            self
                .background(Color.leaveGlassBase, in: shape)
                .overlay {
                    shape
                        .stroke(resolvedTint.opacity(tint == nil ? 0.16 : 0.30), lineWidth: tint == nil ? 1 : 1.2)
                }
                .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self
                .background(Color.leaveGlassBase, in: shape)
                .overlay {
                    shape
                        .stroke(resolvedTint.opacity(tint == nil ? 0.16 : 0.30), lineWidth: tint == nil ? 1 : 1.2)
                }
        }
    }

    @ViewBuilder
    func liquidGlassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        let resolvedTint = tint ?? Color.leaveTeal
        if #available(macOS 26.0, *) {
            self
                .background(Color.leaveGlassBase, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(resolvedTint.opacity(tint == nil ? 0.16 : 0.30), lineWidth: 1)
                }
                .glassEffect(interactive ? .regular.interactive() : .regular, in: Capsule())
        } else {
            self
                .background(Color.leaveGlassBase, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(resolvedTint.opacity(tint == nil ? 0.16 : 0.30), lineWidth: 1)
                }
        }
    }
}


private extension Color {
    static let leaveCanvas = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.941, green: 0.992, blue: 0.980, alpha: 1),
        dark: NSColor(calibratedRed: 0.024, green: 0.086, blue: 0.075, alpha: 1),
    ))
    static let leaveSurface = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.94),
        dark: NSColor(calibratedRed: 0.071, green: 0.157, blue: 0.141, alpha: 1),
    ))
    static let leaveElevated = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.910, green: 0.973, blue: 0.949, alpha: 1),
        dark: NSColor(calibratedRed: 0.102, green: 0.220, blue: 0.196, alpha: 1),
    ))
    static let leaveGlassBase = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.965, green: 0.992, blue: 0.984, alpha: 0.74),
        dark: NSColor(calibratedRed: 0.066, green: 0.176, blue: 0.158, alpha: 0.78),
    ))
    static let leaveInk = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.078, green: 0.306, blue: 0.290, alpha: 1),
        dark: NSColor(calibratedRed: 0.894, green: 0.957, blue: 0.933, alpha: 1),
    ))
    static let leaveMuted = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.230, green: 0.392, blue: 0.372, alpha: 1),
        dark: NSColor(calibratedRed: 0.690, green: 0.805, blue: 0.772, alpha: 1),
    ))
    static let leaveTeal = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.030, green: 0.450, blue: 0.400, alpha: 1),
        dark: NSColor(calibratedRed: 0.176, green: 0.831, blue: 0.749, alpha: 1),
    ))
    static let leaveOrange = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.720, green: 0.270, blue: 0.020, alpha: 1),
        dark: NSColor(calibratedRed: 0.992, green: 0.729, blue: 0.455, alpha: 1),
    ))
}


private extension NSColor {
    static func leaveAdaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua]) == .darkAqua ? dark : light
        }
    }
}
