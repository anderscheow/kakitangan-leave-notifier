import Foundation


enum LaunchAgentService {
    private static let label = "com.kakitangan.leave-notifier"

    static var isWeekdayScheduleInstalled: Bool {
        guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return false
        }
        let agentURL = libraryURL
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent("\(label).plist")
        return FileManager.default.fileExists(atPath: agentURL.path)
    }

    static func isScheduleCurrent(times: [NotificationTime], runAtLogin: Bool) -> Bool {
        guard let agentURL = try? launchAgentURL(),
              let data = try? Data(contentsOf: agentURL),
              let propertyList = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil,
              ) as? [String: Any] else {
            return false
        }
        let installedRunAtLoad = propertyList["RunAtLoad"] as? Bool ?? false
        let installedTimes = Set(
            (propertyList["StartCalendarInterval"] as? [[String: Any]] ?? []).compactMap(scheduleKey),
        )
        let expectedTimes = Set(
            times.flatMap { time in
                (2...6).map { weekday in
                    scheduleKey(weekday: weekday, hour: time.hour, minute: time.minute)
                }
            },
        )
        return installedRunAtLoad == runAtLogin && installedTimes == expectedTimes
    }

    static func installWeekdaySchedule(times: [NotificationTime], runAtLogin: Bool) throws {
        guard !times.isEmpty || runAtLogin else {
            throw NotifierError.automatedCheckNotConfigured
        }
        let applicationURL = try installApplication()
        let launchAgentsURL = try userLibraryURL(component: "LaunchAgents")
        let logsURL = try userLibraryURL(component: "Logs/KakitanganLeaveNotifier")
        try FileManager.default.createDirectory(at: launchAgentsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)

        let schedule = times.flatMap { time in
            (2...6).map { weekday in
                ["Weekday": weekday, "Hour": time.hour, "Minute": time.minute]
            }
        }
        var propertyList: [String: Any] = [
            "Label": label,
            // `-n` forces a new instance: without it, `open` reuses an already-running GUI
            // instance and drops `--args`, so the scheduled check never runs while the app is open.
            "ProgramArguments": ["/usr/bin/open", "-gjn", applicationURL.path, "--args", "--check-leaves"],
            "ProcessType": "Background",
            "StandardOutPath": logsURL.appendingPathComponent("leave-notifier.log").path,
            "StandardErrorPath": logsURL.appendingPathComponent("leave-notifier.error.log").path,
        ]
        if !schedule.isEmpty {
            propertyList["StartCalendarInterval"] = schedule
        }
        if runAtLogin {
            propertyList["RunAtLoad"] = true
        }
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0,
        )
        let agentURL = launchAgentsURL.appendingPathComponent("\(label).plist")
        try data.write(to: agentURL, options: .atomic)
        try runLaunchctl(arguments: ["bootout", "gui/\(getuid())/\(label)"], allowsFailure: true)
        try runLaunchctl(arguments: ["bootstrap", "gui/\(getuid())", agentURL.path], allowsFailure: false)
    }

    static func uninstallWeekdaySchedule() throws {
        let agentURL = try launchAgentURL()
        try runLaunchctl(arguments: ["bootout", "gui/\(getuid())/\(label)"], allowsFailure: true)
        if FileManager.default.fileExists(atPath: agentURL.path) {
            try FileManager.default.removeItem(at: agentURL)
        }
    }

    /// Keeps the `~/Applications` copy that the scheduled LaunchAgent launches in sync with the
    /// running app. After a Sparkle update the installed app changes but this copy does not, so its
    /// resources (including the app icon shown on scheduled notifications) would otherwise go stale.
    static func refreshInstalledApplicationIfNeeded() {
        guard isWeekdayScheduleInstalled else {
            return
        }
        let applicationsURL = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)[0]
        let installedURL = applicationsURL.appendingPathComponent("Kakitangan Leave Notifier.app")
        let source = Bundle.main.bundleURL
        guard source.pathExtension == "app",
              source.standardizedFileURL != installedURL.standardizedFileURL,
              FileManager.default.fileExists(atPath: installedURL.path),
              bundleVersion(at: source) != bundleVersion(at: installedURL) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: installedURL)
            try FileManager.default.copyItem(at: source, to: installedURL)
        } catch {
            // Best-effort refresh; the previous copy remains in place if replacement fails.
        }
    }

    private static func bundleVersion(at url: URL) -> String {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return ""
        }
        let short = plist["CFBundleShortVersionString"] as? String ?? ""
        let build = plist["CFBundleVersion"] as? String ?? ""
        return "\(short)-\(build)"
    }

    private static func installApplication() throws -> URL {
        let applicationsURL = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)[0]
        let installedApplicationURL = applicationsURL.appendingPathComponent("Kakitangan Leave Notifier.app")
        let sourceApplicationURL = Bundle.main.bundleURL
        guard sourceApplicationURL.pathExtension == "app" else {
            throw NotifierError.launchAgentFailed
        }
        if sourceApplicationURL.standardizedFileURL == installedApplicationURL.standardizedFileURL {
            return installedApplicationURL
        }
        try FileManager.default.createDirectory(at: applicationsURL, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: installedApplicationURL.path) {
            try FileManager.default.removeItem(at: installedApplicationURL)
        }
        try FileManager.default.copyItem(at: sourceApplicationURL, to: installedApplicationURL)
        return installedApplicationURL
    }

    private static func userLibraryURL(component: String) throws -> URL {
        guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            throw NotifierError.launchAgentFailed
        }
        return libraryURL.appendingPathComponent(component)
    }

    private static func launchAgentURL() throws -> URL {
        try userLibraryURL(component: "LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }

    private static func scheduleKey(_ entry: [String: Any]) -> String? {
        guard let weekday = entry["Weekday"] as? Int,
              let hour = entry["Hour"] as? Int,
              let minute = entry["Minute"] as? Int else {
            return nil
        }
        return scheduleKey(weekday: weekday, hour: hour, minute: minute)
    }

    private static func scheduleKey(weekday: Int, hour: Int, minute: Int) -> String {
        "\(weekday)-\(hour)-\(minute)"
    }

    private static func runLaunchctl(arguments: [String], allowsFailure: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        if !allowsFailure, process.terminationStatus != 0 {
            throw NotifierError.launchAgentFailed
        }
    }
}
