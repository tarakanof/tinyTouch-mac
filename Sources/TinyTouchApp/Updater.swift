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
    @ObservationIgnored private var observation: NSKeyValueObservation?
    private(set) var canCheckForUpdates = false

    init() {
        #if DEBUG
        // Demo and debug builds never update themselves.
        controller = nil
        #else
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
        observation = controller?.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let value = change.newValue ?? false
            Task { @MainActor in self?.canCheckForUpdates = value }
        }
    }

    var isAvailable: Bool { controller != nil }

    var automaticallyChecksForUpdates: Bool {
        get {
            access(keyPath: \.automaticallyChecksForUpdates)
            return controller?.updater.automaticallyChecksForUpdates ?? false
        }
        set {
            withMutation(keyPath: \.automaticallyChecksForUpdates) {
                controller?.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get {
            access(keyPath: \.automaticallyDownloadsUpdates)
            return controller?.updater.automaticallyDownloadsUpdates ?? false
        }
        set {
            withMutation(keyPath: \.automaticallyDownloadsUpdates) {
                controller?.updater.automaticallyDownloadsUpdates = newValue
            }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
