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
                ScrollView {
                    DashboardView()
                        .padding(32)
                        .frame(maxWidth: 840, alignment: .topLeading)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 18)

            TabView {
                settingsTab {
                    AccountCard()
                    MonitoredEmailsCard()
                }
                .tabItem { Label("Account", systemImage: "person.crop.circle") }

                settingsTab {
                    PermissionCard()
                    NotificationTimesCard()
                    OnDemandChecksCard()
                }
                .tabItem { Label("Notifications", systemImage: "bell") }

                settingsTab {
                    LoginItemCard()
                    AppVisibilityCard()
                    UpdatesCard()
                }
                .tabItem { Label("General", systemImage: "gearshape") }
            }
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
                Text(isEditing ? "Edit your watch" : "Set up your leave watch")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.leaveInk)

                Text(isEditing
                    ? "Update the account, people, time horizon, or weekday check times."
                    : "A focused weekday briefing for the people whose leave affects your work.")
                    .font(.body)
                    .foregroundStyle(.secondary)
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
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Button(isEditing ? "Save changes" : "Save setup") {
                    model.saveSetup()
                }
                .buttonStyle(.borderedProminent)
                .tint(.leaveTeal)
                .controlSize(.large)

                Spacer(minLength: 0)
            }

            Text("Your password is saved only in the macOS Keychain. This app never displays or exports it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}


private struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            dashboardHeader
            scheduleCard

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 210), spacing: 16)],
                spacing: 16,
            ) {
                MetricCard(title: "Account", value: model.accountEmail, icon: "person.crop.circle")
                MetricCard(title: "Watching", value: "\(model.monitoredEmployeeCount) people", icon: "person.2")
                MetricCard(
                    title: "Look ahead",
                    value: "\(model.daysAhead) days",
                    icon: "calendar",
                )
            }

            LeaveListCard()

            if !model.statusMessage.isEmpty {
                StatusMessage(message: model.statusMessage)
            }
        }
        .task {
            await model.refreshWatchList()
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            AppMark()

            VStack(alignment: .leading, spacing: 5) {
                Text("Leave watch")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.leaveInk)
                Text("Your weekday leave briefing is ready when you are.")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                Task { await model.refreshWatchList() }
            } label: {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(model.isRefreshing)
            .help("Refresh leave list")
            .accessibilityLabel("Refresh leave list")

            Button {
                model.beginEditing()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("Settings")
            .accessibilityLabel("Open settings")
        }
    }

    private var scheduleCard: some View {
        SurfaceCard {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: scheduleIcon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(scheduleColor)
                    .frame(width: 46, height: 46)
                    .background(
                        scheduleColor
                            .opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(scheduleTitle)
                        .font(.headline)
                        .foregroundStyle(Color.leaveInk)
                    Text(scheduleDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button(scheduleButtonTitle) {
                    model.installWeekdaySchedule()
                }
                .buttonStyle(.borderedProminent)
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
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } else {
            Text("Your leave list will appear here. Use the refresh button to load it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
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
                Text("\(leave.leaveType) · \(dateText(leave))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            daysLeftBadge(leave, today: today)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.leaveElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(leave.name), \(leave.leaveType), \(dateText(leave)), \(leave.remainingDaysLabel(from: today))")
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
            .background(color.opacity(0.14), in: Capsule())
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
                        .foregroundStyle(.secondary)
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
                    .buttonStyle(.borderedProminent)
                    .tint(.leaveTeal)
                    .disabled(model.isChecking)

                    Button {
                        Task {
                            await model.testNotification()
                        }
                    } label: {
                        Label("Test notification", systemImage: "bell.badge")
                    }
                    .buttonStyle(.bordered)
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
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(Color.leaveTeal)
                    Text("Kakitangan account")
                        .font(.headline)
                        .foregroundStyle(Color.leaveInk)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Login email")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.leaveInk)
                    TextField("name@g2g.com", text: $model.accountEmail)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Kakitangan login email")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Password")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.leaveInk)
                    SecureField("Kakitangan password", text: $model.password)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Kakitangan password")
                    Text("Leave the password blank to keep the one already saved in Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                Text("\(model.monitoredEmployeeCount) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Select the employees to watch. Only approved leave active within the look-ahead window is included.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pickerControls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search name or email", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.leaveElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                Task { await model.loadManagedEmployees() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(model.isLoadingEmployees)
        }
    }

    @ViewBuilder
    private var pickerContent: some View {
        if model.isLoadingEmployees && model.managedEmployees.isEmpty {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading employees…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } else if let error = model.employeeLoadError, model.managedEmployees.isEmpty {
            errorState(error)
        } else if model.managedEmployees.isEmpty {
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
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
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
                    .foregroundStyle(selected ? Color.leaveTeal : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(employee.displayName)
                        .foregroundStyle(Color.leaveInk)
                    Text(employee.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                selected ? Color.leaveTeal.opacity(0.10) : Color.leaveElevated,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous),
            )
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
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("name@g2g.com", text: $newEmail)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addManualEmail)
                    .accessibilityLabel("Add employee email manually")
                Button("Add", action: addManualEmail)
                    .buttonStyle(.bordered)
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
                Text("\(model.monitoredEmployeeCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.leaveTeal)
                    .accessibilityLabel("\(model.monitoredEmployeeCount) selected users")
            }

            if model.monitoredEmployeeCount == 0 {
                Text("No users selected yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
        model.managedEmployees
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
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(role: .destructive) {
                model.setMonitored(employee.email, false)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Remove \(employee.displayName)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.leaveElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(role: .destructive) {
                model.setMonitored(email, false)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Remove \(email)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.leaveElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func errorState(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.leaveOrange)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") {
                    Task { await model.loadManagedEmployees() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.leaveElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
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
                .buttonStyle(.bordered)

                Divider()

                Toggle(isOn: $model.runAtLogin) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Check at sign-in")
                            .foregroundStyle(Color.leaveInk)
                        Text("Runs a hidden leave check after you sign in to this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .accessibilityHint("Enables an automatic background check after you sign in to this Mac.")

                Text("Deleting the final time stops weekday checks. Turn off Check at sign-in too to disable every automatic check; Check now remains available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            .buttonStyle(.bordered)
            .accessibilityLabel("Delete \(model.date(for: notificationTime).formatted(date: .omitted, time: .shortened)) notification time")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.leaveElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    Toggle(
                        "Open Kakitangan Leave Notifier at login",
                        isOn: Binding(
                            get: { model.isOpenAtLoginEnabled },
                            set: { model.setOpenAtLogin($0) },
                        ),
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!model.canConfigureOpenAtLogin)
                    .accessibilityLabel("Open Kakitangan Leave Notifier at login")
                    .accessibilityHint("Adds or removes this app from the Open at Login list in System Settings.")
                }

                HStack(spacing: 12) {
                    Button {
                        model.openLoginItemSettings()
                    } label: {
                        Label("Open Login Items", systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canConfigureOpenAtLogin)

                    Button("Refresh status") {
                        model.refreshLoginItemStatus()
                    }
                    .buttonStyle(.borderless)
                    .disabled(!model.canConfigureOpenAtLogin)
                }

                Text("This opens the app window after you sign in and appears in System Settings → General → Login Items. It is separate from Check at sign-in, which runs a hidden leave check.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            return "Kakitangan Leave Notifier appears in Open at Login and will open after you sign in."
        case .disabled:
            return "Turn this on to add Kakitangan Leave Notifier to Open at Login."
        case .requiresApproval:
            return "macOS needs your approval. Open Login Items and enable Kakitangan Leave Notifier."
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
                    Text("Choose where Kakitangan Leave Notifier stays available while you work. The change applies now; save setup to keep it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Picker(
                    "Show Kakitangan Leave Notifier in",
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
                .accessibilityLabel("Show Kakitangan Leave Notifier in")
                .accessibilityHint("Choose whether the app appears in the Menu Bar, the Dock, or both.")

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: visibilityIcon)
                        .foregroundStyle(Color.leaveTeal)
                        .frame(width: 20)
                    Text(visibilityDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.leaveElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            return "The menu-bar icon is hidden. Open Kakitangan Leave Notifier from the Dock."
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
                        .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .accessibilityHint("Lets Sparkle check for new versions in the background.")

                Button {
                    updater.checkForUpdates()
                } label: {
                    Label("Check for Updates…", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
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
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if model.notificationPermission == .notDetermined {
                    Button("Allow notifications") {
                        Task {
                            await model.requestNotificationPermission()
                        }
                    }
                    .buttonStyle(.borderedProminent)
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
            return "Enable notifications, Time Sensitive alerts, and Persistent alert style in System Settings → Notifications → Kakitangan Leave Notifier."
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
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.leaveInk)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
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
            .background(Color.leaveTeal.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}


private struct SurfaceCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.leaveSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(Color.leaveTeal, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityHidden(true)
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
    static let leaveInk = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.078, green: 0.306, blue: 0.290, alpha: 1),
        dark: NSColor(calibratedRed: 0.894, green: 0.957, blue: 0.933, alpha: 1),
    ))
    static let leaveTeal = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.051, green: 0.580, blue: 0.533, alpha: 1),
        dark: NSColor(calibratedRed: 0.176, green: 0.831, blue: 0.749, alpha: 1),
    ))
    static let leaveOrange = Color(nsColor: .leaveAdaptive(
        light: NSColor(calibratedRed: 0.976, green: 0.451, blue: 0.118, alpha: 1),
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
