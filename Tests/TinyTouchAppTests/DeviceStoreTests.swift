import Testing
import Foundation
@testable import TinyTouchApp

/// A stand-in for the `tinytouch` CLI: a shell script that answers the commands
/// the store sends, and slows down when a flag file is present.
private struct FakeCLI {
    let directory: URL
    let cli: CLI
    /// Unique, so the port another test saved as preferred is never this one.
    let port: String

    init() throws {
        let id = UUID().uuidString
        port = "/dev/cu.usbmodem-\(id)"
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinytouch-fake-\(id)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("tinytouch")
        try (#"""
        #!/bin/sh
        port='\#(port)'
        dir=$(dirname "$0")
        trap 'exit 130' INT
        pause() { if [ -f "$dir/$1" ]; then sleep "$2" >/dev/null 2>&1 & wait; fi; }
        case "$*" in
          "--version") echo "tinyTouch CLI 9.9.9" ;;
          "ports --json") pause slow-ports 0.6; echo "[\"$port\"]" ;;
          "config list --json") echo '{}' ;;
          *" status")
            if [ -f "$dir/no-answer" ]; then echo "Error: tinyTouch did not acknowledge STATUS." >&2; exit 1; fi
            echo '{"mode": "hid", "fingerprints": "4", "hosts": "1", "firmware": "9.9.9"}' ;;
          *" mode hid")
            echo "Touch the device with a registered finger to unlock configuration."
            echo "HID mode was selected."
            echo "Unplug and reconnect tinyTouch to apply the new device mode."
            echo "Waiting for the device to disconnect from USB."
            pause slow-mode 5
            echo "HID mode is active." ;;
          *" config "*)
            echo "$*" >> "$dir/commands"
            echo "Touch the device with a registered finger to unlock configuration."
            pause slow-config 0.3
            if [ -f "$dir/no-match" ]; then echo "Error: No enrolled fingerprint matched." >&2; exit 1; fi
            echo "Updated the settings." ;;
          *" fingers")
            echo "Finger 1: Enrolled: 4 fingerprint views."
            pause slow-fingers 0.3
            echo "Space for 9 additional fingers." ;;
          *" keyboard-layout") echo "HID keyboard layout: auto." ;;
          *" setup "*) pause slow-setup 1; echo '@tinytouch {"event": "ready", "mode": "hid"}' ;;
          *) echo "Error: unexpected command: $*" >&2; exit 1 ;;
        esac
        """#).write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        cli = CLI(executable: script)
    }

    func set(_ flag: String) {
        FileManager.default.createFile(atPath: directory.appendingPathComponent(flag).path, contents: nil)
    }

    func clear(_ flag: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(flag))
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The `config` commands received so far, without the port.
    var configCommands: [String] {
        let log = (try? String(contentsOf: directory.appendingPathComponent("commands"), encoding: .utf8)) ?? ""
        return log.split(separator: "\n").map { $0.replacingOccurrences(of: "--port \(port) ", with: "") }
    }
}

@MainActor
private func wait(until condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(10)
    while !condition() {
        try #require(ContinuousClock.now < deadline, "timed out waiting for the store")
        try await Task.sleep(for: .milliseconds(2))
    }
}

@MainActor
@Test func findsTheDeviceThroughTheCLI() async throws {
    let fake = try FakeCLI()
    defer { fake.remove() }
    let store = DeviceStore(cli: fake.cli)
    await store.refreshAll()
    #expect(store.connection == .connected(port: fake.port))
    #expect(store.cliVersion == "9.9.9")
    #expect(store.status?.mode == .hid)
    #expect(store.fingers.enrolledCount == 1)
    #expect(store.keyboardLayout == "auto")
    #expect(!store.isBusy)
}

@MainActor
@Test func setupReportsDoneAfterReadingTheDevice() async throws {
    let fake = try FakeCLI()
    defer { fake.remove() }
    let store = DeviceStore(cli: fake.cli)
    await store.refreshAll()
    #expect(await store.runSetup(mode: .hid, password: "secret"))
    #expect(store.setupPhase == .done)
}

@MainActor
@Test func setupWithoutADeviceFails() async throws {
    let fake = try FakeCLI()
    defer { fake.remove() }
    let store = DeviceStore(cli: fake.cli)
    #expect(await store.runSetup(mode: .hid, password: "secret") == false)
    guard case .failed = store.setupPhase else {
        Issue.record("expected a failed phase, got \(store.setupPhase)")
        return
    }
}

@MainActor
@Test func leavingSetupStopsTheCLI() async throws {
    let fake = try FakeCLI()
    defer { fake.remove() }
    let store = DeviceStore(cli: fake.cli)
    await store.refreshAll()
    fake.set("slow-setup")
    let started = ContinuousClock.now
    let setup = Task { await store.runSetup(mode: .hid, password: "secret") }
    try await wait { store.isBusy }
    store.resetSetup()
    #expect(await setup.value == false)
    #expect(store.setupPhase == .idle)
    #expect(ContinuousClock.now - started < .milliseconds(900))
}

/// A setup that is left while it re-reads the device must not report into the
/// setup that was started after it.
@MainActor
@Test func aFinishingSetupDoesNotReportIntoTheNextOne() async throws {
    let fake = try FakeCLI()
    defer { fake.remove() }
    let store = DeviceStore(cli: fake.cli)
    await store.refreshAll()

    fake.set("slow-ports")
    let first = Task { await store.runSetup(mode: .hid, password: "secret") }
    try await wait { store.isBusy }
    // The CLI has exited; the first setup is now reading the device again.
    try await wait { !store.isBusy }
    store.resetSetup()

    fake.set("slow-setup")
    let second = Task { await store.runSetup(mode: .hid, password: "secret") }
    #expect(await first.value == false)
    #expect(store.setupPhase == .running("Preparing tinyTouch…"))
    #expect(await second.value)
    #expect(store.setupPhase == .done)
}

/// The port list holds every USB serial device, so one that never answered as
/// tinyTouch is not a tinyTouch that can't be reached.
@MainActor
@Test func anUnknownSerialDeviceIsNotAConnectionError() async throws {
    let fake = try FakeCLI()
    defer { fake.remove() }
    fake.set("no-answer")
    let store = DeviceStore(cli: fake.cli)
    await store.refreshAll()
    #expect(store.connection == .disconnected)
}

@MainActor
@Test func aKnownDeviceThatStopsAnsweringSaysWhy() async throws {
    let fake = try FakeCLI()
    defer { fake.remove() }
    let store = DeviceStore(cli: fake.cli)
    await store.refreshAll()
    #expect(store.port == fake.port)

    fake.set("no-answer")
    await store.refreshAll()
    #expect(store.connection == .failed("tinyTouch did not acknowledge STATUS."))
    #expect(store.status == nil)

    fake.clear("no-answer")
    await store.refreshStatus()
    #expect(store.connection == .connected(port: fake.port))
}

@MainActor
@Test func switchingModeReportsTheSwitch() async throws {
    let fake = try FakeCLI()
    defer { fake.remove() }
    let store = DeviceStore(cli: fake.cli)
    await store.refreshAll()
    await store.setMode(.hid)
    #expect(store.lastMessage == "Switched to Password (HID).")
    #expect(store.touchPrompt == nil)
    #expect(!store.isApproving)
}

/// Cancelling the reconnect wait leaves the mode saved on the device, so the
/// app has to say so.
@MainActor
@Test func cancellingTheReconnectWaitSaysTheModeIsSaved() async throws {
    let fake = try FakeCLI()
    defer { fake.remove() }
    let store = DeviceStore(cli: fake.cli)
    await store.refreshAll()
    fake.set("slow-mode")
    let change = Task { await store.setMode(.hid) }
    try await wait { store.touchPrompt?.kind == .reconnect }
    #expect(store.isApproving)
    store.cancelApproval()
    await change.value
    #expect(store.lastMessage?.hasPrefix("Password (HID) is saved.") == true)
    #expect(store.lastError == nil)
    #expect(!store.isApproving)
}

@MainActor
@Test func savesSeveralSettingsWithOneTouchAndEndsOnAConfirmation() async throws {
    let fake = try FakeCLI()
    defer { fake.remove() }
    let store = DeviceStore(cli: fake.cli)
    await store.refreshAll()
    fake.set("slow-config")
    let apply = Task {
        await store.apply([("led", "off"), ("led_idle_color", "purple"), ("typing_delay_ms", "7")])
    }
    try await wait { store.touchPrompt?.phase == .waiting }
    #expect(store.touchPrompt?.title == "Save 3 settings")
    #expect(store.touchPrompt?.step == "Touch 1 of 2")
    #expect(await apply.value)
    // The lighting mode is saved alone; everything else shares one command and one touch.
    #expect(fake.configCommands == ["config led off", "config led_idle_color purple typing_delay_ms 7"])
    #expect(store.touchPrompt?.phase == .approved)
    #expect(store.lastMessage == "3 settings saved.")
    // An approved prompt is on its way out and can't be cancelled into an error.
    store.cancelApproval()
    #expect(store.touchPrompt?.phase == .approved)
    try await wait { store.touchPrompt == nil }
}

@MainActor
@Test func aRefusedTouchLeavesNoConfirmation() async throws {
    let fake = try FakeCLI()
    defer { fake.remove() }
    let store = DeviceStore(cli: fake.cli)
    await store.refreshAll()
    fake.set("no-match")
    #expect(await store.apply([("typing_delay_ms", "7")]) == false)
    #expect(store.touchPrompt == nil)
    #expect(store.lastError == "No enrolled fingerprint matched.")
    #expect(store.lastMessage == nil)
}

@MainActor
@Test func aReadQueuedBehindAnApprovalLeavesItsPromptAlone() async throws {
    let fake = try FakeCLI()
    defer { fake.remove() }
    let store = DeviceStore(cli: fake.cli)
    await store.refreshAll()
    fake.set("slow-config")
    fake.set("slow-fingers")
    let apply = Task { await store.apply([("typing_delay_ms", "7")]) }
    try await wait { store.touchPrompt?.phase == .waiting }
    // Queued behind the approval, as when a tab opens while the prompt is up.
    var readDone = false
    Task {
        await store.refreshFingers()
        readDone = true
    }
    var approved = false
    var wentBack = false
    while !readDone {
        let phase = store.touchPrompt?.phase
        if phase == .approved { approved = true }
        if approved, phase != nil, phase != .approved { wentBack = true }
        try await Task.sleep(for: .milliseconds(2))
    }
    #expect(await apply.value)
    #expect(approved)
    // The read's output is not the approval's: "Approved" never returns to "Finishing…".
    #expect(!wentBack)
}

@MainActor
@Test func aNameDoesNotOutliveItsFinger() async throws {
    let fake = try FakeCLI()
    defer { fake.remove() }
    let preferences = AppPreferences()
    defer { preferences.keepFingerNames(for: []) }
    preferences.setFingerName("Right index", for: 1)
    // Slot 2 was emptied somewhere else: from another Mac, or with the CLI.
    preferences.setFingerName("Left thumb", for: 2)
    let store = DeviceStore(cli: fake.cli)
    store.preferences = preferences
    await store.refreshAll()
    #expect(preferences.fingerName(1) == "Right index")
    #expect(!preferences.hasFingerName(2))
}
