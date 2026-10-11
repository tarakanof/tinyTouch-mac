import Foundation

struct CLIError: LocalizedError, Sendable {
    let message: String
    let status: Int32

    var errorDescription: String? { message }
}

struct CLIResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String

    var lines: [String] {
        stdout.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
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

    var isBundled: Bool { executable == Self.bundled }

    static func locate() -> CLI? {
        let fm = FileManager.default
        for path in [bundled.path] + searchPaths where fm.isExecutableFile(atPath: path) {
            return CLI(executable: URL(fileURLWithPath: path))
        }
        return nil
    }

    /// Runs one CLI command after any command already in flight finishes.
    /// The device serial port is exclusive, so commands never overlap.
    func run(
        _ arguments: [String],
        input: String? = nil,
        environment: [String: String] = [:],
        onLine: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> CLIResult {
        try await queue.enqueue { [executable] in
            try await Self.execute(executable, arguments, input: input, environment: environment, onLine: onLine)
        }
    }

    /// Runs a command that does not touch the device and may skip the queue.
    func runDetached(_ arguments: [String]) async throws -> CLIResult {
        try await Self.execute(executable, arguments, input: nil, environment: [:], onLine: { _ in })
    }

    private static func execute(
        _ executable: URL,
        _ arguments: [String],
        input: String?,
        environment extra: [String: String],
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> CLIResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        environment["TERM"] = "dumb"
        environment["PYTHONUNBUFFERED"] = "1"
        environment.merge(extra) { _, new in new }
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin

        let outBuffer = LineBuffer(onLine: onLine)
        let errBuffer = LineBuffer(onLine: onLine)
        stdout.fileHandleForReading.readabilityHandler = { outBuffer.append($0.availableData) }
        stderr.fileHandleForReading.readabilityHandler = { errBuffer.append($0.availableData) }

        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                    return
                }
                if let input {
                    stdin.fileHandleForWriting.write(Data(input.utf8))
                }
                try? stdin.fileHandleForWriting.close()
            }
        } onCancel: {
            // SIGINT lets the CLI run its own cleanup, e.g. removing partial enrollment.
            if process.isRunning { process.interrupt() }
        }

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        outBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
        errBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())
        outBuffer.finish()
        errBuffer.finish()

        let result = CLIResult(status: status, stdout: outBuffer.text, stderr: errBuffer.text)
        if Task.isCancelled || status == 130 {
            throw CancellationError()
        }
        guard status == 0 else {
            throw CLIError(message: errorMessage(from: result), status: status)
        }
        return result
    }

    private static func errorMessage(from result: CLIResult) -> String {
        let candidates = result.stderr.split(whereSeparator: \.isNewline).map(String.init)
            + result.lines
        if let line = candidates.first(where: { $0.hasPrefix("Error: ") }) {
            return String(line.dropFirst("Error: ".count))
        }
        let text = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "tinytouch exited with status \(result.status)." : text
    }
}

private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private var collected = Data()
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
    }

    var text: String {
        lock.withLock { String(decoding: collected, as: UTF8.self) }
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        let lines: [String] = lock.withLock {
            collected.append(data)
            pending.append(data)
            var lines: [String] = []
            while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let line = pending[pending.startIndex..<newline]
                lines.append(String(decoding: line, as: UTF8.self))
                pending.removeSubrange(pending.startIndex...newline)
            }
            return lines
        }
        for line in lines { emit(line) }
    }

    func finish() {
        let rest: String? = lock.withLock {
            guard !pending.isEmpty else { return nil }
            defer { pending.removeAll() }
            return String(decoding: pending, as: UTF8.self)
        }
        if let rest { emit(rest) }
    }

    private func emit(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { onLine(trimmed) }
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
