import AppKit
import Foundation
import Observation

enum SettingsTab: String, Hashable {
    case general, lighting, fingers, computers, activity, maintenance, app, about
}

enum Connection: Equatable {
    case noCLI
    case searching
    case disconnected
    case connected(port: String)
    case failed(String)
}

/// Shown while the device waits for a finger on the sensor.
struct TouchPrompt: Equatable {
    var title: String
    var detail: String
    var step: String?
}

/// Progress of `tinytouch setup`, driven by the CLI's app-mode events.
enum SetupPhase: Equatable {
    case idle
    case running(String)
    case reconnect
    case done
    case failed(String)
}

struct EnrollmentProgress: Equatable {
    enum Phase: Equatable {
        case approving
        case touch(view: Int, second: Bool)
        case lift(view: Int)
        case verifying
        case done
        case failed(String)
    }

    let finger: Int
    var phase: Phase = .approving
    var completedScans = 0

    static let viewNames = ["left edge", "right edge", "top", "center"]
}

@MainActor
@Observable
final class DeviceStore {
    private(set) var cli: CLI?
    private(set) var connection: Connection = .searching {
        didSet { announce(from: oldValue) }
    }
    private(set) var status: DeviceStatus? {
        didSet { if let status { config = status.settings } }
    }
    private(set) var config: [String: String] = [:]
    private(set) var catalog: [String: SettingSpec] = [:]
    private(set) var fingers = FingerInventory.empty
    private(set) var hosts = HostList(identifiers: [], capacity: 8)
    private(set) var events: [DeviceEvent] = []
    private(set) var keyboardLayout = "auto"
    private(set) var helperRunning = false
    private(set) var helperInstalled = false
    private(set) var helperExecutable: String?
    private(set) var setupPhase: SetupPhase = .idle
    private(set) var cliVersion = ""
    private(set) var availablePorts: [String] = []

    private(set) var busyCount = 0
    var touchPrompt: TouchPrompt?
    var enrollment: EnrollmentProgress?
    var lastError: String?
    var lastMessage: String?
    var settingsTab: SettingsTab = .general
    var preferences: AppPreferences?
    /// Set when someone asks to run setup again from the main window.
    var setupRequest: DeviceMode??

    private var enrollmentTask: Task<Void, Never>?
    private var approvalTask: Task<CLIResult, Error>?
    private var portWatcher: PortWatcher?
    private var portChangeTask: Task<Void, Never>?
    private var hasConnected = false
    private var helperMigrationAttempted = false

    var isBusy: Bool { busyCount > 0 }

    /// True when the device and this Mac are ready for touch sign-in.
    var isConfigured: Bool {
        guard let status, status.fingerprints > 0 else { return false }
        switch status.mode {
        case .hid: return status.hosts > 0 && helperInstalled
        case .piv: return status.pivReady
        case nil: return false
        }
    }

    var port: String? {
        if case .connected(let port) = connection { return port }
        return nil
    }

    var preferredPort: String? {
        get { UserDefaults.standard.string(forKey: "port") }
        set { UserDefaults.standard.set(newValue, forKey: "port") }
    }

    init() {
        cli = CLI.locate()
        if cli == nil { connection = .noCLI }
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--tab"), index + 1 < arguments.count,
           let tab = SettingsTab(rawValue: arguments[index + 1]) {
            settingsTab = tab
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard portWatcher == nil else { return }
        portWatcher = PortWatcher { [weak self] in self?.portsChanged() }
        portWatcher?.start()
        Task { await refreshAll() }
    }

    func relocateCLI() async {
        cli = CLI.locate()
        connection = cli == nil ? .noCLI : .searching
        if cli != nil { await refreshAll() }
    }

    /// Re-reads `ports --json` shortly after IOKit reports a serial device change.
    /// The delay lets a reconnecting device finish enumerating.
    private func portsChanged() {
        portChangeTask?.cancel()
        portChangeTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let cli,
                  let result = try? await cli.runDetached(["ports", "--json"]) else { return }
            let ports = Self.decodePorts(result.stdout)
            availablePorts = ports
            if let port, !ports.contains(port) {
                connection = .disconnected
                status = nil
            } else if port == nil, !ports.isEmpty, !isBusy {
                await refreshAll()
            }
        }
    }

    // MARK: - Reading state

    func refreshAll() async {
        guard let cli else { connection = .noCLI; return }
        if cliVersion.isEmpty,
           let version = try? await cli.runDetached(["--version"]) {
            cliVersion = version.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "tinyTouch CLI ", with: "")
        }
        if catalog.isEmpty { await loadCatalog() }
        await refreshHelper()
        await migrateHelperIfNeeded()
        // Each device command pauses the HID helper, so read only what the
        // menu and General need; other tabs load their own data.
        guard await resolvePort() else { return }
        await refreshFingers()
        await refreshLayout()
    }

    private func resolvePort() async -> Bool {
        guard let cli else { return false }
        if port == nil { connection = .searching }
        let ports: [String]
        do {
            ports = Self.decodePorts(try await cli.runDetached(["ports", "--json"]).stdout)
        } catch {
            connection = .failed(error.localizedDescription)
            return false
        }
        availablePorts = ports
        guard !ports.isEmpty else {
            connection = .disconnected
            status = nil
            return false
        }
        var candidates = ports
        if let current = port ?? preferredPort, let index = candidates.firstIndex(of: current) {
            candidates.swapAt(0, index)
        }
        for candidate in candidates {
            if let device = try? await readStatus(candidate) {
                status = device
                connection = .connected(port: candidate)
                preferredPort = candidate
                return true
            }
        }
        connection = .disconnected
        status = nil
        return false
    }

    private func readStatus(_ port: String) async throws -> DeviceStatus {
        guard let cli else { throw CLIError(message: "tinytouch CLI not found.", status: 1) }
        let result = try await cli.run(["--port", port, "status"])
        let raw = try JSONDecoder().decode([String: String].self, from: Data(result.stdout.utf8))
        return DeviceStatus(raw: raw)
    }

    func refreshStatus() async {
        guard let port else { return }
        do {
            status = try await readStatus(port)
        } catch {
            report(error)
        }
    }

    private func loadCatalog() async {
        guard let cli, let result = try? await cli.runDetached(["config", "list", "--json"]),
              let decoded = try? JSONDecoder().decode([String: SettingSpec].self, from: Data(result.stdout.utf8))
        else { return }
        catalog = Dictionary(uniqueKeysWithValues: decoded.map { name, spec in
            var spec = spec
            spec.name = name
            return (name, spec)
        })
    }

    func refreshFingers() async {
        guard let result = await device(["fingers"], quiet: true) else { return }
        fingers = FingerInventory.parse(result.lines)
    }

    func refreshHosts() async {
        guard let result = await device(["computers"], quiet: true) else { return }
        hosts = HostList.parse(result.lines)
    }

    func refreshLogs() async {
        guard let result = await device(["logs"], quiet: true) else { return }
        events = DeviceEvent.parse(result.lines)
    }

    func refreshLayout() async {
        guard let result = await device(["keyboard-layout"], quiet: true),
              let line = result.lines.first(where: { $0.hasPrefix("HID keyboard layout:") }) else { return }
        keyboardLayout = line.replacingOccurrences(of: "HID keyboard layout:", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    }

    func refreshHelper() async {
        let wasRunning = helperRunning
        let agent = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/LaunchAgents/com.tinytouch.helper.plist")
        let plist = (try? Data(contentsOf: agent)).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        }
        helperInstalled = plist != nil
        helperExecutable = (plist?["ProgramArguments"] as? [String])?.first
        defer {
            if wasRunning, !helperRunning, helperInstalled {
                preferences?.notify("Password entry stopped", "The tinyTouch background helper isn't running. Open tinyTouch to repair it.")
            }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "gui/\(getuid())/com.tinytouch.helper"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            helperRunning = process.terminationStatus == 0 && text.contains("state = running")
        } catch {
            helperRunning = false
        }
    }

    // MARK: - Writing settings

    /// Applies setting changes one at a time; each write needs its own fingerprint approval.
    func apply(_ changes: [(name: String, value: String)]) async -> Bool {
        for (index, change) in changes.enumerated() {
            let step = changes.count > 1 ? "Change \(index + 1) of \(changes.count)" : nil
            let title = SettingTitles.title(for: change.name).lowercased()
            guard await device(["config", change.name, change.value], approval: "Save \(title)", step: step) != nil else {
                await refreshStatus()
                return false
            }
        }
        await refreshStatus()
        lastMessage = changes.count == 1 ? "Setting saved." : "\(changes.count) settings saved."
        return true
    }

    func setMode(_ mode: DeviceMode) async {
        guard await device(["mode", mode.rawValue], approval: "Switch to \(mode.title)") != nil else { return }
        lastMessage = "Mode saved. Unplug and reconnect tinyTouch to apply it."
        await refreshStatus()
    }

    func setPIVTouch(_ enabled: Bool) async {
        guard await device(["piv-touch", enabled ? "on" : "off"], approval: "Change touch activation") != nil else { return }
        lastMessage = "Saved. Unplug and reconnect tinyTouch to apply it."
        await refreshStatus()
    }

    func setKeyboardLayout(_ layout: String) async {
        guard await device(["keyboard-layout", layout]) != nil else { return }
        await refreshLayout()
    }

    func applyPreset(_ preset: LEDPreset) async {
        guard await device(["led", "preset", preset.rawValue], approval: "Apply \(preset.title) lighting") != nil else { return }
        lastMessage = "\(preset.title) lighting applied."
        await refreshStatus()
    }

    func preview(color: LEDColor, effect: LEDEffect, durationMs: Int) async {
        _ = await device(
            ["led", "preview", color.rawValue, "--effect", effect.rawValue, "--duration-ms", String(durationMs)],
            approval: "Preview lighting"
        )
    }

    // MARK: - Fingers

    func enroll(finger: Int, replace: Bool) {
        guard let port, enrollmentTask == nil else { return }
        enrollment = EnrollmentProgress(finger: finger)
        var arguments = ["--port", port, "enroll", String(finger)]
        if replace { arguments.append("--replace") }
        enrollmentTask = Task {
            busyCount += 1
            defer {
                busyCount -= 1
                enrollmentTask = nil
            }
            do {
                _ = try await cli?.run(arguments) { line in
                    Task { @MainActor in self.handleEnrollment(line) }
                }
                enrollment?.phase = .done
                await refreshFingers()
                await refreshStatus()
            } catch is CancellationError {
                enrollment = nil
                await refreshFingers()
            } catch {
                enrollment?.phase = .failed(error.localizedDescription)
                await refreshFingers()
            }
        }
    }

    func cancelEnrollment() {
        if let enrollmentTask {
            enrollmentTask.cancel()
        } else {
            enrollment = nil
        }
    }

    private func handleEnrollment(_ line: String) {
        guard var progress = enrollment else { return }
        let view: Int = switch progress.phase {
        case .touch(let view, _), .lift(let view): view
        default: 1
        }
        if line.hasPrefix("Touch the device with a registered finger") {
            progress.phase = .approving
        } else if line.hasPrefix("Finger "), line.contains(": View ") {
            let number = line.components(separatedBy: ": View ").last?
                .split(separator: " ").first.flatMap { Int($0) } ?? view
            progress.phase = .touch(view: number, second: false)
        } else if line.hasPrefix("Touch the sensor again") {
            progress.phase = .touch(view: view, second: true)
        } else if line.hasPrefix("Touch the sensor") {
            progress.phase = .touch(view: view, second: false)
        } else if line.hasPrefix("Lift your finger") {
            if case .touch = progress.phase { progress.completedScans += 1 }
            progress.phase = progress.completedScans >= 8 ? .verifying : .lift(view: view)
        }
        enrollment = progress
    }

    func deleteFinger(_ finger: Int) async {
        guard await device(["delete", String(finger)], approval: "Delete finger \(finger)") != nil else { return }
        lastMessage = "Finger \(finger) deleted."
        await refreshFingers()
    }

    // MARK: - Computers and maintenance

    func removeHost(_ identifier: String) async {
        guard await device(["computers", "remove", identifier], approval: "Remove computer") != nil else { return }
        lastMessage = "Computer removed."
        await refreshHosts()
        await refreshStatus()
    }

    /// Moves a helper installed by a standalone CLI onto the CLI inside this app.
    /// Runs once per launch and only succeeds without prompting when Keychain
    /// already trusts the bundled CLI's signature.
    private func migrateHelperIfNeeded() async {
        guard !helperMigrationAttempted, let cli, cli.isBundled, helperInstalled,
              let helperExecutable, helperExecutable != cli.executable.path else { return }
        helperMigrationAttempted = true
        do {
            _ = try await cli.run(["--app", "_upgrade-helper"])
            await refreshHelper()
        } catch {
            needsKeychainPassword = true
        }
    }

    /// Set when Keychain must be unlocked to let this app's CLI read saved credentials.
    var needsKeychainPassword = false

    /// Reinstalls the helper. Keychain asks for the login password only when the
    /// saved credentials don't trust this CLI yet.
    func repairHelper(keychainPassword: String? = nil) async {
        guard let cli else { return }
        let asked = Flag()
        await perform {
            var arguments = ["--app", "repair"]
            if let port { arguments += ["--port", port] }
            do {
                _ = try await cli.run(arguments, input: keychainPassword.map { $0 + "\n" }) { line in
                    if line.contains(#""event": "keychain_password""#) { asked.set() }
                }
            } catch {
                guard asked.isSet, keychainPassword == nil else { throw error }
                needsKeychainPassword = true
                return
            }
            needsKeychainPassword = false
            lastMessage = "Background helper reinstalled."
        }
        await refreshHelper()
    }

    // MARK: - Setup and password

    /// Runs `tinytouch setup` without enrollment; the app enrolls fingers itself.
    func runSetup(mode: DeviceMode, password: String?) async -> Bool {
        guard let cli, let port else { return false }
        setupPhase = .running("Preparing tinyTouch…")
        var arguments = ["--app", "--port", port, "setup", "--mode", mode.rawValue, "--skip-enroll"]
        if mode == .piv, status?.mode == .piv, status?.pivReady == true { arguments.append("--no-pair") }
        var succeeded = false
        await perform(quiet: true) {
            do {
                _ = try await cli.run(
                    arguments,
                    input: password.map { $0 + "\n" },
                    environment: ["SUDO_ASKPASS": CLI.askpass.path]
                ) { line in
                    Task { @MainActor in self.handleSetup(line) }
                }
                succeeded = true
            } catch {
                setupPhase = .failed(error.localizedDescription)
            }
        }
        touchPrompt = nil
        if succeeded { setupPhase = .done }
        await refreshAll()
        return succeeded
    }

    func resetSetup() {
        setupPhase = .idle
    }

    private func handleSetup(_ line: String) {
        guard line.hasPrefix("@tinytouch "),
              let data = line.dropFirst("@tinytouch ".count).data(using: .utf8),
              let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let name = event["event"] as? String else {
            handlePrompt(line, approval: "Approve setup", step: nil)
            return
        }
        switch name {
        case "reconnect_needed": setupPhase = .reconnect
        case "reconnected": setupPhase = .running("Finishing setup…")
        case "piv_creating": setupPhase = .running("Creating the smart card identity. This can take up to 30 seconds.")
        case "admin_authorization": setupPhase = .running("Waiting for your administrator password…")
        case "installing_helper": setupPhase = .running("Installing the background helper…")
        default: break
        }
    }

    /// Saves a new typed password. The app confirms it before calling this.
    func changePassword(_ password: String, finger: Int?) async -> Bool {
        var arguments = ["password"]
        if let finger { arguments += ["--finger", String(finger)] }
        guard let cli, let port else { return false }
        var saved = false
        await perform {
            _ = try await cli.run(["--app", "--port", port] + arguments, input: password + "\n")
            saved = true
        }
        if saved {
            lastMessage = finger.map { "Password saved for finger \($0)." } ?? "Password saved."
        }
        return saved
    }

    func uninstallHelper() async {
        guard let cli else { return }
        await perform { _ = try await cli.run(["uninstall"]) }
        await refreshHelper()
    }

    func factoryReset() async {
        guard await device(["factory-reset"], input: "y\n", approval: "Factory reset") != nil else { return }
        lastMessage = "tinyTouch was reset. Run setup to use it again."
        await refreshAll()
    }

    // MARK: - Plumbing

    @discardableResult
    private func device(
        _ arguments: [String],
        input: String? = nil,
        approval: String? = nil,
        step: String? = nil,
        quiet: Bool = false
    ) async -> CLIResult? {
        guard let cli, let port else { return nil }
        var result: CLIResult?
        await perform(quiet: quiet) {
            let task = Task {
                try await cli.run(["--port", port] + arguments, input: input) { line in
                    Task { @MainActor in
                        self.handlePrompt(line, approval: approval, step: step)
                    }
                }
            }
            if approval != nil { approvalTask = task }
            defer { if approval != nil { approvalTask = nil } }
            result = try await task.value
        }
        touchPrompt = nil
        return result
    }

    /// Cancels a command that is waiting for fingerprint approval.
    func cancelApproval() {
        approvalTask?.cancel()
        touchPrompt = nil
    }

    private func handlePrompt(_ line: String, approval: String?, step: String?) {
        if line.hasPrefix("Touch the device with a registered finger") {
            touchPrompt = TouchPrompt(
                title: approval ?? "Approve on tinyTouch",
                detail: "Touch the sensor with an enrolled finger.",
                step: step
            )
        } else if line.hasPrefix("Lift your finger"), touchPrompt != nil {
            touchPrompt?.detail = "Lift your finger."
        }
    }

    private func perform(quiet: Bool = false, _ operation: () async throws -> Void) async {
        busyCount += 1
        defer { busyCount -= 1 }
        do {
            try await operation()
        } catch is CancellationError {
        } catch {
            if !quiet { report(error) }
        }
    }

    private func announce(from previous: Connection) {
        switch (previous, connection) {
        case (.connected, .connected):
            break
        case (_, .connected):
            if hasConnected { preferences?.notify("tinyTouch connected", "Touch sign-in is available.") }
            hasConnected = true
        case (.connected, .disconnected):
            preferences?.notify("tinyTouch disconnected", "Touch sign-in is unavailable until you reconnect it.")
        default:
            break
        }
    }

    private func report(_ error: Error) {
        lastError = error.localizedDescription
    }

    private static func decodePorts(_ json: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
