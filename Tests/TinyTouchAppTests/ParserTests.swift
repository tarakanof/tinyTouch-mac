import Testing
import Foundation
@testable import TinyTouchApp

private func lines(_ text: String) -> [String] {
    ProcessOutput(status: 0, stdout: text, stderr: "").lines
}

@Test func parsesFingerInventory() {
    let inventory = FingerInventory.parse(lines("""
    Finger 1: Enrolled: 4 fingerprint views.
    Finger 3: Partially enrolled: 2 of 4 fingerprint views.
    Finger 4: Cleanup pending. Reconnect the device.
    Space for 7 additional fingers.
    """))
    #expect(inventory.fingers[0].state == .enrolled)
    #expect(inventory.fingers[1].state == .empty)
    #expect(inventory.fingers[2].state == .partial(2))
    #expect(inventory.fingers[3].state == .cleanupPending)
    #expect(inventory.available == 7)
    #expect(inventory.enrolledCount == 3)
}

@Test func parsesEmptyFingerInventory() {
    let inventory = FingerInventory.parse(lines("No fingerprints enrolled.\nSpace for 10 additional fingers.\n"))
    #expect(inventory.enrolledCount == 0)
    #expect(inventory.available == 10)
}

@Test func parsesIndentedHostList() {
    let hosts = HostList.parse(lines("HID computers (1 of 8):\n  a1b2c3d4e5f60718\n"))
    #expect(hosts.identifiers == ["a1b2c3d4e5f60718"])
    #expect(hosts.capacity == 8)
}

@Test func parsesNoHosts() {
    let hosts = HostList.parse(lines("No HID computers are registered.\n"))
    #expect(hosts.identifiers.isEmpty)
}

@Test func parsesDeviceLogNewestFirst() {
    let events = DeviceEvent.parse(lines("""
    LOG ms=155 event=task_started value=0
    LOG ms=83368 event=finger_matched value=1
    LOG ms=89369 event=hid_failed value=1
    """))
    #expect(events.map(\.name) == ["hid_failed", "finger_matched", "task_started"])
    #expect(events[1].title == "Finger 1 matched")
    #expect(events[1].uptimeText == "1:23")
}

@Test func decodesSettingsCatalog() throws {
    let json = """
    {"mode": {"default": "piv", "values": ["piv", "hid"], "description": "Mode.", "requires_new_firmware": false},
     "typing_delay_ms": {"default": 1, "values": {"minimum": 1, "maximum": 100}, "description": "Delay.", "requires_new_firmware": false}}
    """
    let catalog = try JSONDecoder().decode([String: SettingSpec].self, from: Data(json.utf8))
    #expect(catalog["typing_delay_ms"]?.range == 1...100)
    #expect(catalog["typing_delay_ms"]?.defaultValue.description == "1")
    #expect(catalog["mode"]?.defaultValue.description == "piv")
}

@Test func decodesSettingsFromRawStatus() {
    let status = DeviceStatus(raw: [
        "led": "on", "led_idle_color": "1", "led_success_color": "2", "led_failure_color": "4",
        "led_idle_end_color": "6", "led_idle_effect": "3", "submit_enter": "1", "piv_auto_type": "0",
        "typing_delay_ms": "7", "firmware": "0.1.35",
    ])
    #expect(status.settings["led_idle_color"] == "blue")
    #expect(status.settings["led_failure_color"] == "red")
    #expect(status.settings["led_idle_end_color"] == "yellow")
    #expect(status.settings["led_idle_effect"] == "steady")
    #expect(status.settings["submit_enter"] == "on")
    #expect(status.settings["piv_auto_type"] == "off")
    #expect(status.settings["typing_delay_ms"] == "7")
    #expect(status.settings["firmware"] == nil)
}

@Test func groupsDeviceEventsForFiltering() {
    let events = DeviceEvent.parse([
        "LOG ms=1000 event=touch_detected value=0",
        "LOG ms=2000 event=finger_no_match value=0",
        "LOG ms=3000 event=hid_typing value=0",
        "LOG ms=4000 event=usb_attached value=0",
    ])
    let names: (DeviceEvent.Category) -> [String] = { category in
        events.filter { $0.belongs(to: category) }.map(\.name)
    }
    #expect(names(.all).count == 4)
    #expect(names(.fingerprints) == ["finger_no_match", "touch_detected"])
    #expect(names(.passwords) == ["hid_typing"])
    #expect(names(.problems) == ["finger_no_match"])
    #expect(names(.device) == ["usb_attached"])
    #expect(events.first { $0.name == "hid_typing" }?.title == "Typing password")
}

@Test func parsesHostListWithThisMac() {
    let hosts = HostList.parse([
        "HID computers (2 of 8):",
        "  0123456789abcdef",
        "  fedcba9876543210  (this Mac)",
    ])
    #expect(hosts.capacity == 8)
    #expect(hosts.identifiers == ["0123456789abcdef", "fedcba9876543210"])
    #expect(hosts.local == "fedcba9876543210")
}

/// What `tinytouch enroll 2` prints outside a terminal, following the firmware's
/// events: a lift before each view, then touch, lift, touch again.
private let enrollmentTranscript = """
Touch the device with a registered finger to unlock configuration.
Lift your finger away from the sensor.
Finger 2: View 1 of 4.
Touch the sensor with the left edge of the same finger.
Lift your finger away from the sensor.
Touch the sensor again with the left edge of the same finger.
Lift your finger away from the sensor.
Finger 2: View 2 of 4.
Touch the sensor with the right edge of the same finger.
Lift your finger away from the sensor.
Touch the sensor again with the right edge of the same finger.
Lift your finger away from the sensor.
Finger 2: View 3 of 4.
Touch the sensor with the top of the same finger.
Lift your finger away from the sensor.
Touch the sensor again with the top of the same finger.
Lift your finger away from the sensor.
Finger 2: View 4 of 4.
Touch the sensor with the center of the same finger.
Lift your finger away from the sensor.
Touch the sensor again with the center of the same finger.
Finger 2 is enrolled with all four views.
"""

@Test func followsEnrollmentToCompletion() {
    var progress = EnrollmentProgress(finger: 2)
    var phases: [EnrollmentProgress.Phase] = []
    for line in lines(enrollmentTranscript) {
        progress.follow(line)
        if phases.last != progress.phase { phases.append(progress.phase) }
    }
    #expect(phases.prefix(5) == [
        .approving, .lift(view: 1), .touch(view: 1, second: false), .lift(view: 1), .touch(view: 1, second: true),
    ])
    // The device sends nothing after the last scan, so one is still open here.
    #expect(progress.phase == .touch(view: 4, second: true))
    #expect(progress.completedScans == EnrollmentProgress.totalScans - 1)

    progress.finish()
    #expect(progress.phase == .done)
    #expect(progress.completedScans == EnrollmentProgress.totalScans)
}

@Test func touchPromptEndsWithTheNextLine() {
    var prompt = TouchPrompt.after(
        "Touch the device with a registered finger to unlock configuration.",
        current: nil, approval: "Save typing delay", step: "Change 1 of 2"
    )
    #expect(prompt?.title == "Save typing delay")
    #expect(prompt?.step == "Change 1 of 2")
    prompt = TouchPrompt.after("Lift your finger away from the sensor.", current: prompt, approval: nil, step: nil)
    #expect(prompt?.detail == "Lift your finger.")
    prompt = TouchPrompt.after("Updated typing_delay_ms to 7.", current: prompt, approval: nil, step: nil)
    #expect(prompt == nil)
}

/// What `tinytouch mode hid` prints. The sheet must stay up from the touch to
/// the end, so there is never a line that leaves no prompt.
@Test func modeSwitchKeepsOnePromptUntilTheCommandEnds() {
    var prompt: TouchPrompt?
    var kinds: [TouchPrompt.Kind?] = []
    for line in lines("""
    Touch the device with a registered finger to unlock configuration.
    HID mode was selected.
    Unplug and reconnect tinyTouch to apply the new device mode.
    Waiting for the device to disconnect from USB.
    The device disconnected. Waiting for it to reconnect.
    HID mode is active.
    """) {
        prompt = TouchPrompt.after(line, current: prompt, approval: "Switch to Password (HID)", step: nil)
        kinds.append(prompt?.kind)
    }
    #expect(kinds == [.touch, .reconnect, .reconnect, .reconnect, .reconnect, .reconnect])
    #expect(prompt?.title == "Reconnect tinyTouch")
    #expect(prompt?.symbol == "cable.connector.slash")
    #expect(prompt?.detail == "Plug tinyTouch back in.")
}

@Test func setupNeverShowsTheReconnectPrompt() {
    // Setup shows its own reconnect page, driven by the CLI's app events.
    var prompt = TouchPrompt.after(
        "Touch the device with a registered finger to unlock configuration.",
        current: nil, approval: "Approve setup", step: nil
    )
    for line in ["Unplug and reconnect tinyTouch to use HID mode.", "The device disconnected. Waiting for it to reconnect."] {
        prompt = TouchPrompt.after(line, current: prompt, approval: "Approve setup", step: nil)
        #expect(prompt == nil)
    }
}

@Test func liftWithoutAPromptShowsNothing() {
    #expect(TouchPrompt.after("Lift your finger away from the sensor.", current: nil, approval: nil, step: nil) == nil)
}
