import Testing
import Foundation
@testable import TinyTouchApp

private func lines(_ text: String) -> [String] {
    CLIResult(status: 0, stdout: text, stderr: "").lines
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
