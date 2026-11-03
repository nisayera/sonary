import AppKit
import Observation
import Sparkle

/// Wraps Sparkle: checks for updates automatically and lets the user install one with a click.
@MainActor
@Observable
final class UpdateModel {
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecks: Bool

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init(startUpdater: Bool) {
        controller = SPUStandardUpdaterController(startingUpdater: startUpdater, updaterDelegate: nil, userDriverDelegate: nil)
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        canCheckForUpdates = controller.updater.canCheckForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.canCheckForUpdates = self.controller.updater.canCheckForUpdates
            }
        }
    }

    func checkForUpdates() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecks(_ on: Bool) {
        controller.updater.automaticallyChecksForUpdates = on
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
