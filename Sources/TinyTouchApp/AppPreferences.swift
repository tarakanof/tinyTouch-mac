import AppKit
import Observation
import ServiceManagement
import UserNotifications

/// Optional rows and shortcuts in the menu bar window.
enum MenuItem: String, CaseIterable, Identifiable {
    case mode, fingerprints, helper, firmware, port
    case fingerprintsShortcut, activityShortcut

    var id: String { rawValue }

    static let status: [MenuItem] = [.mode, .fingerprints, .helper, .firmware, .port]
    static let shortcuts: [MenuItem] = [.fingerprintsShortcut, .activityShortcut]
    static let defaults: Set<MenuItem> = [.mode, .fingerprints, .helper, .firmware, .fingerprintsShortcut]

    var title: String {
        switch self {
        case .mode: "Mode"
        case .fingerprints: "Enrolled fingers"
        case .helper: "Background helper or smart card"
        case .firmware: "Firmware version"
        case .port: "USB port"
        case .fingerprintsShortcut: "Fingerprints…"
        case .activityShortcut: "Activity…"
        }
    }

    var symbol: String {
        switch self {
        case .mode: "lock.shield.fill"
        case .fingerprints: "touchid"
        case .helper: "gearshape.2.fill"
        case .firmware: "memorychip.fill"
        case .port: "cable.connector"
        case .fingerprintsShortcut: "touchid"
        case .activityShortcut: "list.bullet.rectangle"
        }
    }
}

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

    var menuItems: Set<MenuItem> {
        didSet { UserDefaults.standard.set(menuItems.map(\.rawValue), forKey: "menuItems") }
    }

    /// Crosses out the menu bar icon while tinyTouch is disconnected.
    var showsDisconnectedIcon: Bool {
        didSet { UserDefaults.standard.set(showsDisconnectedIcon, forKey: "showsDisconnectedIcon") }
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
        defaults.register(defaults: [
            "showInMenuBar": true, "notifications": false, "hasCompletedSetup": false,
            "showsDisconnectedIcon": true, "menuItems": MenuItem.defaults.map(\.rawValue),
        ])
        showInMenuBar = defaults.bool(forKey: "showInMenuBar")
        notificationsEnabled = defaults.bool(forKey: "notifications")
        menuItems = Set((defaults.stringArray(forKey: "menuItems") ?? []).compactMap(MenuItem.init))
        showsDisconnectedIcon = defaults.bool(forKey: "showsDisconnectedIcon")
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

    func shows(_ item: MenuItem) -> Bool { menuItems.contains(item) }

    func setShows(_ item: MenuItem, _ shown: Bool) {
        if shown { menuItems.insert(item) } else { menuItems.remove(item) }
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

    /// Picks up a change made in System Settings › Notifications while the app was in the background.
    func refreshNotificationStatus() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        let wasDenied = notificationsDenied
        notificationsDenied = status == .denied
        if status == .denied {
            notificationsEnabled = false
        } else if wasDenied, status == .authorized || status == .provisional {
            notificationsEnabled = true
        }
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
