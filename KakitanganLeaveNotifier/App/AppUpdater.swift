import Combine
import Foundation
import Sparkle


@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var lastUpdateCheckDate: Date?

    private let updaterController: SPUStandardUpdaterController
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        // Background leave-check launches (`--check-leaves`, `--test-notification`) still build the
        // SwiftUI window hierarchy, so keep Sparkle dormant there to avoid an update prompt appearing
        // inside a process that is meant to stay invisible.
        let isBackgroundLaunch = ProcessInfo.processInfo.arguments.contains { argument in
            argument == "--check-leaves" || argument == "--test-notification"
        }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: !isBackgroundLaunch,
            updaterDelegate: nil,
            userDriverDelegate: nil,
        )

        let updater = updaterController.updater
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &cancellables)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
            .store(in: &cancellables)
        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.lastUpdateCheckDate = $0 }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
    }
}
