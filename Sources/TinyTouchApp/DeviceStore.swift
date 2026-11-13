import AppKit
import Foundation
import Observation

enum SettingsTab: String, Hashable {
    case general, lighting, fingers, computers, activity, maintenance, app, menu, about
}

enum Connection: Equatable {
    case noCLI
    case searching
    case disconnected
    case connected(port: String)
    case failed(String)
}

/// Shown while a command waits for the person: a finger on the sensor, or a reconnect.
struct TouchPrompt: Equatable {
    enum Kind: Equatable {
        /// Waiting for a finger. Over as soon as the CLI prints anything else,
        /// because it prints nothing when the touch is accepted.
        case touch
        /// Waiting for tinyTouch to be unplugged and plugged back in, which
        /// `tinytouch mode` does until it exits. Stays up until the command ends.
        case reconnect
    }

    var title: String
    var detail: String
    var step: String?
    var kind = Kind.touch

    var symbol: String {
        switch kind {
        case .touch: "touchid"
        case .reconnect: "cable.connector.slash"
        }
    }

    /// The prompt to show once the CLI has printed `line`.
    static func after(_ line: String, current: TouchPrompt?, approval: String?, step: String?) -> TouchPrompt? {
        if line.hasPrefix("Touch the device with a registered finger") {
            return TouchPrompt(
                title: approval ?? "Approve on tinyTouch",
                detail: "Touch the sensor with an enrolled finger.",
                step: step
            )
        }
        if var prompt = current, prompt.kind == .reconnect {
            if line.hasPrefix("The device disconnected") { prompt.detail = "Plug tinyTouch back in." }
            return prompt
        }
        if isModeSaved(line) || line.hasPrefix("Waiting for the device to disconnect") {
            return TouchPrompt(
                title: "Reconnect tinyTouch",
                detail: "Unplug tinyTouch, then plug it back in.",
                kind: .reconnect
            )
        }
        if line.hasPrefix("Lift your finger") {
            var prompt = current
            prompt?.detail = "Lift your finger."
            return prompt
        }
        return nil
    }

    /// `tinytouch mode` prints this once the device has stored the new mode,
    /// just before it starts waiting for the reconnect.
    static func isModeSaved(_ line: String) -> Bool {
        line.hasSuffix(" mode was selected.")
    }
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
        case done
        case failed(String)
    }

    let finger: Int
    var phase: Phase = .approving
    var completedScans = 0

    static let viewNames = ["left edge", "right edge", "top", "center"]
    /// Each of the four views is scanned twice.
    static let totalScans = viewNames.count * 2

    /// Follows one line of `tinytouch enroll` output, e.g. "Finger 2: View 1 of 4."
    mutating func follow(_ line: String) {
        let view: Int = switch phase {
        case .touch(let view, _), .lift(let view): view
        default: 1
        }
        if line.hasPrefix("Touch the device with a registered finger") {
            phase = .approving
        } else if line.hasPrefix("Finger "), line.contains(": View ") {
            let number = line.components(separatedBy: ": View ").last?
                .split(separator: " ").first.flatMap { Int($0) } ?? view
            phase = .touch(view: number, second: false)
        } else if line.hasPrefix("Touch the sensor again") {
            phase = .touch(view: view, second: true)
        } else if line.hasPrefix("Touch the sensor") {
            phase = .touch(view: view, second: false)
        } else if line.hasPrefix("Lift your finger") {
            if case .touch = phase { completedScans += 1 }
            phase = .lift(view: view)
        }
    }

    /// The device reports nothing after the last scan, so the CLI exiting cleanly
    /// is what completes it.
    mutating func finish() {
        completedScans = Self.totalScans
        phase = .done
    }
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
    /// nil until the list has been read; a failed read keeps the last good list.
    private(set) var hosts: HostList?
    private(set) var hostsReadFailed = false
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

    // Each of these is the CLI run itself, so cancelling one interrupts only that
    // command and never the refreshes that follow it.
    private var enrollmentRun: Task<ProcessOutput, Error>?
    private var approvalTask: Task<ProcessOutput, Error>?
    /// The setup that owns `setupPhase`, from its start until it has published
    /// its result. Leaving setup clears it, which disowns a run still finishing.
    private var setupRun: Task<ProcessOutput, Error>?
    private var portWatcher: PortWatcher?
    private var portChangeTask: Task<Void, Never>?
    /// A device appeared while a command was running; look for it once that ends.
    private var portChangePending = false
    private var hasConnected = false
    private var helperMigrationAttempted = false

    var isBusy: Bool { busyCount > 0 }
    /// True while a command that needs a touch is running.
    var isApproving: Bool { approvalTask != nil }

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

    init(cli: CLI? = CLI.locate()) {
        self.cli = cli
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
            guard !Task.isCancelled else { return }
            // Only the wait is cancellable; a later change must not cut a refresh short.
            portChangeTask = nil
            await rescanPorts()
        }
    }

    private func rescanPorts() async {
        guard let cli, let result = try? await cli.runDetached(["ports", "--json"]) else { return }
        let ports = Self.decodePorts(result.stdout)
        availablePorts = ports
        if let port, !ports.contains(port) {
            connection = .disconnected
            status = nil
        } else if port == nil, !ports.isEmpty {
            // A running command, such as setup waiting for a reconnect, owns the port.
            if isBusy { portChangePending = true } else { await refreshAll() }
        }
    }

    /// Switches to another connected tinyTouch.
    func selectPort(_ selected: String) async {
        preferredPort = selected
        if port != selected {
            connection = .searching
            status = nil
            hosts = nil
            events = []
        }
        await refreshAll()
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
        // The port list holds every USB serial device. Only one that has answered
        // as tinyTouch before, or that the person picked, is known to be one.
        let known = port ?? preferredPort
        var candidates = ports
        if let known, let index = candidates.firstIndex(of: known) {
            candidates.swapAt(0, index)
        }
        var failure: Error?
        for candidate in candidates {
            do {
                status = try await readStatus(candidate)
                connection = .connected(port: candidate)
                preferredPort = candidate
                return true
            } catch {
                if candidate == known { failure = error }
            }
        }
        // tinyTouch is plugged in but didn't answer, so say why rather than
        // asking for a cable that is already connected.
        connection = failure.map { .failed($0.localizedDescription) } ?? .disconnected
        status = nil
        return false
    }

    private func readStatus(_ port: String) async throws -> DeviceStatus {
        guard let cli else { throw CLIError(message: "tinytouch CLI not found.", status: 1) }
        let result = try await cli.run(["--port", port, "status"])
        let raw = try JSONDecoder().decode([String: String].self, from: Data(result.stdout.utf8))
        return DeviceStatus(raw: raw)
    }

    /// `quiet` is for refreshes nobody asked for, which must not raise an alert.
    func refreshStatus(quiet: Bool = false) async {
        guard let port else {
            // The device may have reconnected while a command held the port.
            await refreshAll()
            return
        }
        do {
            status = try await readStatus(port)
        } catch {
            if !quiet { report(error) }
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
        guard let result = await device(["computers"], quiet: true) else {
            hostsReadFailed = hosts == nil
            return
        }
        hosts = HostList.parse(result.lines)
        hostsReadFailed = false
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
        let agent = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/LaunchAgents/com.tinytouch.helper.plist")
        let plist = (try? Data(contentsOf: agent)).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        }
        helperInstalled = plist != nil
        helperExecutable = (plist?["ProgramArguments"] as? [String])?.first
        let service = try? await Subprocess.run(
            URL(fileURLWithPath: "/bin/launchctl"), ["print", "gui/\(getuid())/com.tinytouch.helper"]
        )
        let wasRunning = helperRunning
        helperRunning = service?.status == 0 && service?.stdout.contains("state = running") == true
        if wasRunning, !helperRunning, helperInstalled {
            preferences?.notify("Password entry stopped", "The tinyTouch background helper isn't running. Open tinyTouch to repair it.")
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

    /// `tinytouch mode` saves the mode, then waits for tinyTouch to be reconnected
    /// before it installs or removes what the mode needs on this Mac.
    func setMode(_ mode: DeviceMode) async {
        var saved = false
        let result = await device(["mode", mode.rawValue], approval: "Switch to \(mode.title)") { line in
            if TouchPrompt.isModeSaved(line) { saved = true }
        }
        if result != nil {
            lastMessage = "Switched to \(mode.title)."
        } else if saved, lastError == nil {
            // Cancelled during the reconnect wait: the device switches at its next
            // reconnect, but the CLI never got to finish on this Mac.
            lastMessage = mode == .hid
                ? "\(mode.title) is saved. Reconnect tinyTouch, then choose Repair if the background helper isn't running."
                : "\(mode.title) is saved. Reconnect tinyTouch to apply it."
        }
        // Also after a failure: the mode may be saved and only the reconnect missing.
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
        guard let cli, let port, enrollmentRun == nil else { return }
        enrollment = EnrollmentProgress(finger: finger)
        var arguments = ["--port", port, "enroll", String(finger)]
        if replace { arguments.append("--replace") }
        let run = Task {
            try await cli.run(arguments) { line in self.enrollment?.follow(line) }
        }
        enrollmentRun = run
        Task {
            var enrolled = false
            await perform(quiet: true) {
                defer { enrollmentRun = nil }
                do {
                    _ = try await run.value
                    enrollment?.finish()
                    enrolled = true
                } catch is CancellationError {
                    enrollment = nil
                } catch {
                    enrollment?.phase = .failed(error.localizedDescription)
                }
            }
            await refreshFingers()
            if enrolled { await refreshStatus() }
        }
    }

    func cancelEnrollment() {
        if let enrollmentRun {
            enrollmentRun.cancel()
        } else {
            enrollment = nil
        }
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
              let helperExecutable, !Self.isSameFile(helperExecutable, cli.executable.path) else { return }
        helperMigrationAttempted = true
        // Any other failure leaves the old helper running; Repair reports the reason.
        if (try? await installHelper(["--app", "_upgrade-helper"], keychainPassword: nil)) == false {
            needsKeychainPassword = true
        }
        await refreshHelper()
    }

    /// Set when Keychain must be unlocked to let this app's CLI read saved credentials.
    var needsKeychainPassword = false

    /// Reinstalls the helper. Keychain asks for the login password only when the
    /// saved credentials don't trust this CLI yet.
    func repairHelper(keychainPassword: String? = nil) async {
        await perform {
            var arguments = ["--app", "repair"]
            if let port { arguments += ["--port", port] }
            needsKeychainPassword = try await !installHelper(arguments, keychainPassword: keychainPassword)
            if !needsKeychainPassword { lastMessage = "Background helper reinstalled." }
        }
        await refreshHelper()
    }

    /// Runs a helper install command in app mode. Returns false when it stopped
    /// only because Keychain wants the login password and none was given.
    private func installHelper(_ arguments: [String], keychainPassword: String?) async throws -> Bool {
        guard let cli else { throw CLIError(message: "tinytouch CLI not found.", status: 1) }
        var askedForPassword = false
        do {
            _ = try await cli.run(arguments, input: keychainPassword.map { $0 + "\n" }) { line in
                if line.contains(#""event": "keychain_password""#) { askedForPassword = true }
            }
            return true
        } catch {
            guard askedForPassword, keychainPassword == nil else { throw error }
            return false
        }
    }

    // MARK: - Setup and password

    /// Runs `tinytouch setup` without enrollment; the app enrolls fingers itself.
    func runSetup(mode: DeviceMode, password: String?) async -> Bool {
        guard let cli, let port else {
            setupPhase = .failed("tinyTouch isn't connected. Connect it with a USB data cable, then try again.")
            return false
        }
        setupPhase = .running("Preparing tinyTouch…")
        let arguments = ["--app", "--port", port, "setup", "--mode", mode.rawValue, "--skip-enroll"]
        let run = Task {
            try await cli.run(
                arguments,
                input: password.map { $0 + "\n" },
                environment: ["SUDO_ASKPASS": CLI.askpass.path]
            ) { line in self.handleSetup(line) }
        }
        setupRun = run
        var outcome = SetupPhase.done
        await perform(quiet: true) {
            do {
                _ = try await run.value
            } catch is CancellationError {
                outcome = .idle
            } catch {
                outcome = .failed(error.localizedDescription)
            }
        }
        touchPrompt = nil
        if setupRun == run, outcome != .done { setupPhase = outcome }
        // Setup is done only once the device has been read again: the page after
        // it depends on the enrolled fingers.
        await refreshAll()
        // Setup was left, or started again, while this run was finishing.
        guard setupRun == run else { return false }
        setupRun = nil
        if outcome == .done { setupPhase = .done }
        return outcome == .done
    }

    /// Leaves setup: stops the CLI if it is still running, and keeps a run that
    /// is finishing from reporting into whatever comes next.
    func resetSetup() {
        setupRun?.cancel()
        setupRun = nil
        setupPhase = .idle
    }

    private func handleSetup(_ line: String) {
        guard line.hasPrefix("@tinytouch "),
              let data = line.dropFirst("@tinytouch ".count).data(using: .utf8),
              let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let name = event["event"] as? String else {
            touchPrompt = TouchPrompt.after(line, current: touchPrompt, approval: "Approve setup", step: nil)
            return
        }
        // A milestone means the touch that allowed it has already happened.
        touchPrompt = nil
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
        quiet: Bool = false,
        onLine: @escaping @MainActor (String) -> Void = { _ in }
    ) async -> ProcessOutput? {
        guard let cli, let port else { return nil }
        // One approval at a time: the sheet could not cancel a second one queued behind it.
        guard approval == nil || approvalTask == nil else { return nil }
        var result: ProcessOutput?
        await perform(quiet: quiet) {
            let task = Task {
                try await cli.run(["--port", port] + arguments, input: input) { line in
                    self.touchPrompt = TouchPrompt.after(line, current: self.touchPrompt, approval: approval, step: step)
                    onLine(line)
                }
            }
            if approval != nil { approvalTask = task }
            defer { if approval != nil { approvalTask = nil } }
            result = try await task.value
        }
        touchPrompt = nil
        return result
    }

    /// Cancels the command that is waiting for fingerprint approval or a reconnect.
    func cancelApproval() {
        approvalTask?.cancel()
        setupRun?.cancel()
        touchPrompt = nil
    }

    private func perform(quiet: Bool = false, _ operation: () async throws -> Void) async {
        busyCount += 1
        defer {
            busyCount -= 1
            if busyCount == 0, portChangePending {
                portChangePending = false
                portsChanged()
            }
        }
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

    private static func isSameFile(_ first: String, _ second: String) -> Bool {
        URL(fileURLWithPath: first).resolvingSymlinksInPath().path
            == URL(fileURLWithPath: second).resolvingSymlinksInPath().path
    }
}
