import Testing
import Foundation
@testable import TinyTouchApp

@MainActor
private final class Lines {
    var seen: [String] = []
}

private let shell = URL(fileURLWithPath: "/bin/sh")

@Test func splitsLinesAcrossChunks() {
    var splitter = LineSplitter()
    let bytes = Array("  first\n\nsecönd\nlast".utf8)
    // Cut inside the two-byte "ö" to prove lines are decoded whole.
    let cut = bytes.firstIndex(of: 0xC3)! + 1
    #expect(splitter.append(Data(bytes[..<cut])) == ["first"])
    #expect(splitter.append(Data(bytes[cut...])) == ["secönd"])
    #expect(splitter.finish() == "last")
    #expect(splitter.finish() == nil)
    #expect(splitter.text == "  first\n\nsecönd\nlast")
}

@Test func collectsOutputAndStatus() async throws {
    let lines = Lines()
    let output = try await Subprocess.run(shell, ["-c", "echo one; echo two; echo oops >&2; exit 3"]) { line in
        lines.seen.append(line)
    }
    #expect(output.status == 3)
    #expect(output.stdout == "one\ntwo\n")
    #expect(output.stderr == "oops\n")
    // Every line was delivered before the run returned, in order within a stream.
    let seen = await lines.seen
    #expect(seen.filter { $0 != "oops" } == ["one", "two"])
    #expect(seen.contains("oops"))
}

@Test func keepsOutputWrittenJustBeforeExit() async throws {
    for _ in 0..<20 {
        let output = try await Subprocess.run(shell, ["-c", "i=0; while [ $i -lt 400 ]; do echo line $i; i=$((i+1)); done"])
        #expect(output.lines.count == 400)
        #expect(output.lines.last == "line 399")
    }
}

@Test func passesInputToTheChild() async throws {
    let output = try await Subprocess.run(URL(fileURLWithPath: "/bin/cat"), [], input: "secret\n")
    #expect(output.stdout == "secret\n")
}

@Test func survivesAChildThatNeverReadsItsInput() async throws {
    let input = String(repeating: "x", count: 4096)
    for _ in 0..<20 {
        let output = try await Subprocess.run(URL(fileURLWithPath: "/usr/bin/true"), [], input: input)
        #expect(output.status == 0)
    }
}

@Test func cancellingInterruptsAndKeepsTheOutput() async throws {
    let lines = Lines()
    // A second SIGINT would end the script with 99 instead of letting it clean up.
    let script = "trap 'trap \"exit 99\" INT; echo cleaned; exit 130' INT; echo ready; while :; do :; done"
    let run = Task {
        try await Subprocess.run(shell, ["-c", script]) { line in lines.seen.append(line) }
    }
    while await !lines.seen.contains("ready") {
        try await Task.sleep(for: .milliseconds(10))
    }
    run.cancel()
    let output = try await run.value
    #expect(output.status == 130)
    #expect(output.lines == ["ready", "cleaned"])
}

@Test func stopsReadingWhenALeftoverProcessHoldsThePipe() async throws {
    let started = ContinuousClock.now
    let output = try await Subprocess.run(shell, ["-c", "sleep 30 & echo done"])
    #expect(output.status == 0)
    #expect(output.lines == ["done"])
    #expect(ContinuousClock.now - started < .seconds(15))
}

@Test func cancelledBeforeLaunchStillInterrupts() async throws {
    let run = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await Subprocess.run(shell, ["-c", "trap 'exit 130' INT; sleep 30 & wait"])
    }
    let started = ContinuousClock.now
    let output = try await run.value
    #expect(output.status != 0)
    #expect(ContinuousClock.now - started < .seconds(10))
}

@Test func reportsALaunchFailure() async {
    await #expect(throws: (any Error).self) {
        try await Subprocess.run(URL(fileURLWithPath: "/nonexistent/tinytouch"), [])
    }
}
