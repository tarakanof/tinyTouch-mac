import AppKit
import Foundation
import Observation

enum SettingsTab: String, Hashable {
    case general, lighting, fingers, computers, maintenance
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
    private(set) var connection: Connection = .searching
    private(set) var status: DeviceStatus?
    private(set) var config: [String: String] = [:]
    private(set) var catalog: [String: SettingSpec] = [:]
    private(set) var fingers = FingerInventory.empty
    private(set) var hosts = HostList(identifiers: [], capacity: 8)
    private(set) var events: [DeviceEvent] = []
    private(set) var keyboardLayout = "auto"
    private(set) var helperRunning = false
    private(set) var cliVersion = ""
    private(set) var availablePorts: [String] = []

    private(set) var busyCount = 0
    var touchPrompt: TouchPrompt?
    var enrollment: EnrollmentProgress?
    var lastError: String?
    var lastMessage: String?
    var settingsTab: SettingsTab = .general

    private var enrollmentTask: Task<Void, Never>?
    private var approvalTask: Task<CLIResult, Error>?
    private var watchTask: Task<Void, Never>?

    var isBusy: Bool { busyCount > 0 }

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
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            await self?.refreshAll()
            await self?.watchPorts()
        }
    }

    func relocateCLI() async {
        cli = CLI.locate()
        connection = cli == nil ? .noCLI : .searching
        if cli != nil { await refreshAll() }
    }

    /// Polls `ports --json`, which lists serial paths without opening them,
    /// so plug and unplug are noticed without interrupting the HID helper.
    private func watchPorts() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard let cli, !isBusy else { continue }
            guard let result = try? await cli.runDetached(["ports", "--json"]) else { continue }
            let ports = Self.decodePorts(result.stdout)
            guard ports != availablePorts else { continue }
            availablePorts = ports
            if let port, !ports.contains(port) {
                connection = .disconnected
                status = nil
            } else if port == nil, !ports.isEmpty {
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
        guard await resolvePort() else { return }
        await refreshStatus()
        await refreshConfig()
        await refreshFingers()
        await refreshHosts()
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

    func refreshConfig() async {
        guard let result = await device(["config", "--json"], quiet: true) else { return }
        if let values = try? JSONDecoder().decode([String: String].self, from: Data(result.stdout.utf8)) {
            config = values
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
                await refreshConfig()
                return false
            }
        }
        await refreshConfig()
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
        await refreshConfig()
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

    func repairHelper() async {
        guard let cli else { return }
        await perform {
            var arguments = ["repair"]
            if let port { arguments = ["--port", port] + arguments }
            _ = try await cli.run(arguments)
        }
        await refreshHelper()
        if lastError == nil { lastMessage = "HID helper reinstalled." }
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

    /// Opens Terminal for commands that read a password or need an interactive terminal.
    func openInTerminal(_ arguments: [String]) {
        guard let cli else { return }
        var command = [cli.executable.path]
        if let port { command += ["--port", port] }
        command += arguments
        let script = """
        #!/bin/zsh
        clear
        \(command.map(Self.shellQuote).joined(separator: " "))
        echo
        echo "You can close this window."
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinytouch-\(arguments.first ?? "command")-\(UUID().uuidString.prefix(8)).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            report(error)
        }
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

    private func report(_ error: Error) {
        lastError = error.localizedDescription
    }

    private static func decodePorts(_ json: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
