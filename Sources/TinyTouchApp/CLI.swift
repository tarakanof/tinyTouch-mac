import Foundation

struct CLIError: LocalizedError, Sendable {
    let message: String
    let status: Int32

    var errorDescription: String? { message }
}

/// Runs the `tinytouch` CLI bundled in the app, or an installed one during development.
/// The CLI owns the serial protocol, the HID helper lease, and Keychain access, so the
/// app never opens the port itself.
final class CLI: Sendable {
    static let bundled = Bundle.main.bundleURL
        .appendingPathComponent("Contents/Resources/tinytouch/tinytouch")
    static let askpass = Bundle.main.bundleURL
        .appendingPathComponent("Contents/Helpers/tinytouch-askpass")

    static let searchPaths = [
        "\(NSHomeDirectory())/.local/bin/tinytouch",
        "/opt/homebrew/bin/tinytouch",
        "/usr/local/bin/tinytouch",
    ]

    let executable: URL
    private let queue = SerialQueue()

    init(executable: URL) {
        self.executable = executable
    }

    var isBundled: Bool { executable.path == Self.bundled.path }

    static func locate() -> CLI? {
        let fm = FileManager.default
        for path in [bundled.path] + searchPaths where fm.isExecutableFile(atPath: path) {
            return CLI(executable: URL(fileURLWithPath: path))
        }
        return nil
    }

    /// Runs one CLI command after any command already in flight finishes.
    /// The device serial port is exclusive, so commands never overlap.
    /// `onLine` has seen every output line, in order, by the time this returns.
    func run(
        _ arguments: [String],
        input: String? = nil,
        environment: [String: String] = [:],
        onLine: @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> ProcessOutput {
        try await queue.enqueue { [executable] in
            try await Self.execute(executable, arguments, input: input, environment: environment, onLine: onLine)
        }
    }

    /// Runs a command that does not touch the device and may skip the queue.
    func runDetached(_ arguments: [String]) async throws -> ProcessOutput {
        try await Self.execute(executable, arguments, input: nil, environment: [:], onLine: { _ in })
    }

    private static func execute(
        _ executable: URL,
        _ arguments: [String],
        input: String?,
        environment extra: [String: String],
        onLine: @escaping @MainActor (String) -> Void
    ) async throws -> ProcessOutput {
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        environment["TERM"] = "dumb"
        environment["PYTHONUNBUFFERED"] = "1"
        environment.merge(extra) { _, new in new }

        // Cancelling sends SIGINT, which lets the CLI run its own cleanup, e.g.
        // removing a partial enrollment; it then exits with status 130.
        let result = try await Subprocess.run(
            executable, arguments, input: input, environment: environment, onLine: onLine
        )
        // A command that finished before the interrupt landed changed the device,
        // so it counts as done rather than cancelled.
        if result.status == 0 { return result }
        if Task.isCancelled || result.status == 130 { throw CancellationError() }
        throw CLIError(message: errorMessage(from: result), status: result.status)
    }

    private static func errorMessage(from result: ProcessOutput) -> String {
        let candidates = result.stderr.split(whereSeparator: \.isNewline).map(String.init)
            + result.lines
        if let line = candidates.first(where: { $0.hasPrefix("Error: ") }) {
            return String(line.dropFirst("Error: ".count))
        }
        let text = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "tinytouch exited with status \(result.status)." : text
    }
}

private actor SerialQueue {
    private var tail: Task<Void, Never>?

    func enqueue<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<T, Error> {
            await previous?.value
            try Task.checkCancellation()
            return try await operation()
        }
        tail = Task { _ = try? await task.value }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
