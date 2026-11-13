import Foundation
import Observation
import Sparkle

/// Sparkle, checking the appcast attached to the latest GitHub release
/// (`SUFeedURL` in Info.plist). Updates are verified with the EdDSA key in
/// `SUPublicEDKey` and must carry the same Developer ID signature as this app.
@MainActor
@Observable
final class Updater {
    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    private(set) var canCheckForUpdates = false

    /// Mirrors Sparkle's setting, which its own windows can also change.
    var automaticallyChecksForUpdates = false {
        didSet {
            guard let updater = controller?.updater,
                  updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    /// Mirrors Sparkle's setting, which the "Automatically download and install
    /// updates in the future" box in its update window also changes.
    var automaticallyDownloadsUpdates = false {
        didSet {
            guard let updater = controller?.updater,
                  updater.automaticallyDownloadsUpdates != automaticallyDownloadsUpdates else { return }
            updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        }
    }

    init() {
        #if DEBUG
        // Demo and debug builds never update themselves.
        controller = nil
        #else
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
        guard let updater = controller?.updater else { return }
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor in self?.canCheckForUpdates = value }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor in
                    if self?.automaticallyChecksForUpdates != value { self?.automaticallyChecksForUpdates = value }
                }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.initial, .new]) { [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor in
                    if self?.automaticallyDownloadsUpdates != value { self?.automaticallyDownloadsUpdates = value }
                }
            },
        ]
    }

    var isAvailable: Bool { controller != nil }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
