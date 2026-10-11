import AppKit
import Observation
import ServiceManagement
import UserNotifications

/// App behaviour that belongs to this Mac rather than to the device.
@MainActor
@Observable
final class AppPreferences {
    var showInMenuBar: Bool {
        didSet {
            UserDefaults.standard.set(showInMenuBar, forKey: "showInMenuBar")
            applyActivationPolicy()
        }
    }

    var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notifications") }
    }

    var hasCompletedSetup: Bool {
        didSet { UserDefaults.standard.set(hasCompletedSetup, forKey: "hasCompletedSetup") }
    }

    private(set) var loginItemStatus: SMAppService.Status = .notRegistered
    private(set) var notificationsDenied = false
    private(set) var commandLineToolPath: String?
    var mainWindowOpen = false {
        didSet { applyActivationPolicy() }
    }

    static let commandLineToolLink = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".local/bin/tinytouch")

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["showInMenuBar": true, "notifications": false, "hasCompletedSetup": false])
        showInMenuBar = defaults.bool(forKey: "showInMenuBar")
        notificationsEnabled = defaults.bool(forKey: "notifications")
        hasCompletedSetup = defaults.bool(forKey: "hasCompletedSetup")
        // An installed helper means setup already ran, possibly from the CLI.
        if !hasCompletedSetup, FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Library/LaunchAgents/com.tinytouch.helper.plist") {
            hasCompletedSetup = true
        }
        refresh()
    }

    func refresh() {
        loginItemStatus = SMAppService.mainApp.status
        commandLineToolPath = try? FileManager.default.destinationOfSymbolicLink(
            atPath: Self.commandLineToolLink.path
        )
    }

    /// A Dock icon appears while the main window is open, or always when the menu bar icon is off.
    func applyActivationPolicy() {
        NSApp.setActivationPolicy(showInMenuBar && !mainWindowOpen ? .accessory : .regular)
    }

    // MARK: - Open at login

    var openAtLogin: Bool {
        loginItemStatus == .enabled || loginItemStatus == .requiresApproval
    }

    func setOpenAtLogin(_ enabled: Bool) throws {
        defer { refresh() }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Notifications

    func setNotifications(_ enabled: Bool) async {
        guard enabled else {
            notificationsEnabled = false
            return
        }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        notificationsDenied = !granted
        notificationsEnabled = granted
    }

    func notify(_ title: String, _ body: String) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func openNotificationSettings() {
        let bundle = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundle)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Command-line tool

    var commandLineToolInstalled: Bool {
        commandLineToolPath == CLI.bundled.path
    }

    /// Points ~/.local/bin/tinytouch at the CLI inside this app.
    func installCommandLineTool() throws {
        defer { refresh() }
        let fm = FileManager.default
        let link = Self.commandLineToolLink
        try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil || fm.fileExists(atPath: link.path) {
            try fm.removeItem(at: link)
        }
        try fm.createSymbolicLink(at: link, withDestinationURL: CLI.bundled)
    }
}
