import Foundation

struct ProcessOutput: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String

    var lines: [String] {
        stdout.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// Runs a child process to completion without blocking the caller's thread.
enum Subprocess {
    /// How long to keep reading after the child exits. Something it started may
    /// still hold the pipes open, and must not stall the caller for as long as it lives.
    static let drainTime: Duration = .seconds(2)

    /// `onLine` gets each non-empty output line, in order within a stream, and has
    /// handled all of them by the time this returns. Cancelling the task sends one
    /// SIGINT so the child can clean up; its output and exit status still come back.
    static func run(
        _ executable: URL,
        _ arguments: [String],
        input: String? = nil,
        environment: [String: String]? = nil,
        onLine: @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin

        // Each reader runs until end-of-file, so output that arrives as the child
        // exits is neither lost nor reordered.
        let outputs = [stdout.fileHandleForReading, stderr.fileHandleForReading]
        let readers = outputs.map { handle in
            let chunks = Self.chunks(from: handle)
            return Task { await Self.collect(chunks, onLine: onLine) }
        }
        let stopReading = { @Sendable in
            for handle in outputs { handle.readabilityHandler = nil }
            for reader in readers { reader.cancel() }
        }

        let interrupt = Interrupt(process)
        let status: Int32
        do {
            status = try await withTaskCancellationHandler {
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
                    interrupt.launched()
                    Self.write(input, to: stdin.fileHandleForWriting)
                }
            } onCancel: {
                interrupt.request()
            }
        } catch {
            // Nothing launched, so no end-of-file is coming.
            stopReading()
            throw error
        }
        let deadline = Task {
            try await Task.sleep(for: drainTime)
            stopReading()
        }
        defer { deadline.cancel() }
        return ProcessOutput(status: status, stdout: await readers[0].value, stderr: await readers[1].value)
    }

    private static func chunks(from handle: FileHandle) -> AsyncStream<Data> {
        AsyncStream { continuation in
            handle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
        }
    }

    private static func collect(
        _ chunks: AsyncStream<Data>,
        onLine: @escaping @MainActor (String) -> Void
    ) async -> String {
        var splitter = LineSplitter()
        for await chunk in chunks {
            for line in splitter.append(chunk) { await onLine(line) }
        }
        if let rest = splitter.finish() { await onLine(rest) }
        return splitter.text
    }

    private static func write(_ input: String?, to handle: FileHandle) {
        // A child that exits without reading would otherwise end this app with SIGPIPE.
        _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
        if let input { try? handle.write(contentsOf: Data(input.utf8)) }
        try? handle.close()
    }
}

/// Splits output that arrives in arbitrary chunks into trimmed, non-empty lines.
struct LineSplitter {
    private var pending = Data()
    private var collected = Data()

    var text: String { String(decoding: collected, as: UTF8.self) }

    mutating func append(_ data: Data) -> [String] {
        collected.append(data)
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            if let line = Self.line(pending[pending.startIndex..<newline]) { lines.append(line) }
            pending.removeSubrange(pending.startIndex...newline)
        }
        return lines
    }

    /// The last line, when the output didn't end with a newline.
    mutating func finish() -> String? {
        defer { pending.removeAll() }
        return Self.line(pending)
    }

    private static func line(_ bytes: Data) -> String? {
        let line = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? nil : line
    }
}

/// Sends SIGINT exactly once, and only after launch: interrupting a process that
/// hasn't launched raises, and a second signal would cut the child's cleanup short.
private final class Interrupt: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var isLaunched = false
    private var isRequested = false

    init(_ process: Process) {
        self.process = process
    }

    func launched() {
        let send = lock.withLock {
            isLaunched = true
            return isRequested
        }
        if send { process.interrupt() }
    }

    func request() {
        let send = lock.withLock {
            defer { isRequested = true }
            return isLaunched && !isRequested
        }
        if send { process.interrupt() }
    }
}
