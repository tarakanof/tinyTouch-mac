import AppKit
import Observation
import ServiceManagement
import UserNotifications

/// Optional rows and shortcuts in the menu bar window.
enum MenuItem: String, CaseIterable, Identifiable {
    case mode, fingerprints, helper, firmware, port
    case light
    case fingerprintsShortcut, activityShortcut

    var id: String { rawValue }

    static let status: [MenuItem] = [.mode, .fingerprints, .helper, .firmware, .port]
    static let controls: [MenuItem] = [.light]
    static let shortcuts: [MenuItem] = [.fingerprintsShortcut, .activityShortcut]
    static let defaults: Set<MenuItem> = [.mode, .fingerprints, .helper, .firmware, .fingerprintsShortcut]

    var title: String {
        switch self {
        case .mode: "Mode"
        case .fingerprints: "Enrolled fingers"
        case .helper: "Background helper or smart card"
        case .firmware: "Firmware version"
        case .port: "USB port"
        case .light: "Sensor light switch"
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
        case .light: "lightbulb.fill"
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

    /// Names people give finger slots and registered computers. The device stores
    /// neither, so they live on this Mac.
    private var fingerNames: [String: String] {
        didSet { UserDefaults.standard.set(fingerNames, forKey: "fingerNames") }
    }

    private var computerNames: [String: String] {
        didSet { UserDefaults.standard.set(computerNames, forKey: "computerNames") }
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
        fingerNames = defaults.dictionary(forKey: "fingerNames") as? [String: String] ?? [:]
        computerNames = defaults.dictionary(forKey: "computerNames") as? [String: String] ?? [:]
        // An installed helper means setup already ran, possibly from the CLI.
        if !hasCompletedSetup, FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Library/LaunchAgents/com.tinytouch.helper.plist") {
            hasCompletedSetup = true
            // Observers don't run during init, and the helper may be gone next launch.
            defaults.set(true, forKey: "hasCompletedSetup")
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

    // MARK: - Names

    func fingerName(_ finger: Int) -> String {
        fingerNames[String(finger)] ?? "Finger \(finger)"
    }

    func hasFingerName(_ finger: Int) -> Bool {
        fingerNames[String(finger)] != nil
    }

    /// An empty or nil name goes back to "Finger N".
    func setFingerName(_ name: String?, for finger: Int) {
        fingerNames[String(finger)] = Self.cleaned(name)
    }

    /// Forgets the name of every slot that isn't in `fingers`.
    func keepFingerNames(for fingers: [Int]) {
        let kept = fingerNames.filter { fingers.contains(Int($0.key) ?? 0) }
        if kept.count != fingerNames.count { fingerNames = kept }
    }

    func computerName(_ identifier: String) -> String? {
        computerNames[identifier]
    }

    func setComputerName(_ name: String?, for identifier: String) {
        computerNames[identifier] = Self.cleaned(name)
    }

    private static func cleaned(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : String(trimmed.prefix(40))
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
