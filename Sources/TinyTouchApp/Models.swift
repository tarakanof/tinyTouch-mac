import Foundation
import SwiftUI

enum DeviceMode: String, CaseIterable, Identifiable, Sendable {
    case hid, piv

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hid: "Password (HID)"
        case .piv: "Smart Card (PIV)"
        }
    }

    var summary: String {
        switch self {
        case .hid: "Types your Mac password after a fingerprint match. Works with most prompts."
        case .piv: "Signs in with a fingerprint-gated smart card key. Your password is never typed."
        }
    }
}

struct DeviceStatus: Sendable {
    let raw: [String: String]

    var firmware: String { raw["firmware"] ?? "—" }
    var build: String { raw["build"] ?? "—" }
    var mode: DeviceMode? { raw["mode"].flatMap(DeviceMode.init) }
    var pivReady: Bool { raw["piv"] == "ready" }
    var sensorReady: Bool { raw["sensor"] == "ready" }
    var hosts: Int { Int(raw["hosts"] ?? "") ?? 0 }
    var fingerprints: Int { Int(raw["fingerprints"] ?? "") ?? 0 }
    var pivTouch: Bool { raw["piv_touch"] == "on" }
    var pivTouchActive: Bool { raw["piv_touch_active"] == "on" }
    var pivVisible: Bool { raw["piv_visible"] == "yes" }
    var ota: String { raw["ota"] ?? "idle" }
    var ledSync: String { raw["led_sync"] ?? "" }
    var supportsCustomConfig: Bool { raw["custom_config"] == "1" }

    private static let colorNames = ["off", "blue", "green", "cyan", "red", "purple", "yellow", "white"]
    private static let effectNames = [1: "breathe", 2: "flash", 3: "steady", 5: "fade-in", 6: "fade-out"]
    private static let settingKeys = [
        "mode", "led", "piv_delay_ms", "typing_delay_ms", "submit_enter", "touch_cooldown_ms",
        "led_idle_color", "led_success_color", "led_failure_color", "led_idle_end_color",
        "led_idle_effect", "led_idle_cycles", "led_feedback_ms", "piv_auto_type",
    ]

    /// Settings named as `tinytouch config` reports them, decoded from raw status
    /// so reading them doesn't need a second device command.
    var settings: [String: String] {
        var values: [String: String] = [:]
        for key in Self.settingKeys {
            guard let value = raw[key] else { continue }
            switch key {
            case "submit_enter", "piv_auto_type":
                values[key] = value == "1" ? "on" : "off"
            case let color where color.hasSuffix("_color"):
                values[key] = Int(value).flatMap { Self.colorNames[safe: $0] } ?? value
            case "led_idle_effect":
                values[key] = Int(value).flatMap { Self.effectNames[$0] } ?? value
            default:
                values[key] = value
            }
        }
        return values
    }
}

enum JSONScalar: Decodable, Sendable, CustomStringConvertible {
    case string(String)
    case number(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    var description: String {
        switch self {
        case .string(let value): value
        case .number(let value): value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value): value ? "on" : "off"
        }
    }
}

struct SettingSpec: Decodable, Sendable, Identifiable {
    enum Values: Decodable, Sendable {
        case choices([String])
        case range(ClosedRange<Int>)

        private struct Bounds: Decodable {
            let minimum: Int
            let maximum: Int
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let choices = try? container.decode([String].self) {
                self = .choices(choices)
            } else {
                let bounds = try container.decode(Bounds.self)
                self = .range(bounds.minimum...bounds.maximum)
            }
        }
    }

    var name: String = ""
    let defaultValue: JSONScalar
    let values: Values
    let description: String

    var id: String { name }

    var range: ClosedRange<Int> {
        if case .range(let range) = values { return range }
        return 0...0
    }

    enum CodingKeys: String, CodingKey {
        case defaultValue = "default"
        case values, description
    }
}

enum LEDColor: String, CaseIterable, Identifiable, Sendable {
    case off, blue, green, cyan, red, purple, yellow, white

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var swatch: Color {
        switch self {
        case .off: .secondary.opacity(0.25)
        case .blue: .blue
        case .green: .green
        case .cyan: .cyan
        case .red: .red
        case .purple: .purple
        case .yellow: .yellow
        case .white: .white
        }
    }
}

enum LEDEffect: String, CaseIterable, Identifiable, Sendable {
    case steady, breathe, flash
    case fadeIn = "fade-in"
    case fadeOut = "fade-out"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steady: "Steady"
        case .breathe: "Breathe"
        case .flash: "Flash"
        case .fadeIn: "Fade In"
        case .fadeOut: "Fade Out"
        }
    }
}

enum LEDMode: String, CaseIterable, Identifiable, Sendable {
    case on
    case onlyAuth = "only-auth"
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .on: "Always On"
        case .onlyAuth: "Only During Authentication"
        case .off: "Off"
        }
    }
}

enum LEDPreset: String, CaseIterable, Identifiable, Sendable {
    case `default`, ocean, neon, sunset

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct Finger: Identifiable, Sendable {
    enum State: Sendable, Equatable {
        case empty
        case enrolled
        case partial(Int)
        case cleanupPending
    }

    let number: Int
    var state: State

    var id: Int { number }
    var isOccupied: Bool { state != .empty }
}

struct FingerInventory: Sendable {
    var fingers: [Finger]
    var available: Int

    static let empty = FingerInventory(
        fingers: (1...10).map { Finger(number: $0, state: .empty) },
        available: 0
    )

    var enrolledCount: Int { fingers.filter(\.isOccupied).count }

    /// Parses `tinytouch fingers`, e.g. "Finger 1: Enrolled: 4 fingerprint views."
    static func parse(_ lines: [String]) -> FingerInventory {
        var inventory = FingerInventory.empty
        for line in lines {
            if line.hasPrefix("Space for "),
               let count = Int(line.dropFirst("Space for ".count).prefix(while: \.isNumber)) {
                inventory.available = count
                continue
            }
            guard line.hasPrefix("Finger "),
                  let colon = line.firstIndex(of: ":"),
                  let number = Int(line[line.index(line.startIndex, offsetBy: 7)..<colon]),
                  (1...10).contains(number) else { continue }
            let detail = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let state: Finger.State
            if detail.hasPrefix("Enrolled") {
                state = .enrolled
            } else if detail.hasPrefix("Partially enrolled") {
                let views = detail.split(separator: " ").compactMap { Int($0) }.first ?? 0
                state = .partial(views)
            } else if detail.hasPrefix("Cleanup pending") {
                state = .cleanupPending
            } else {
                continue
            }
            inventory.fingers[number - 1].state = state
        }
        return inventory
    }
}

struct HostList: Sendable {
    var identifiers: [String]
    var capacity: Int

    /// Parses `tinytouch computers`, e.g. "HID computers (1 of 8):" followed by IDs.
    static func parse(_ lines: [String]) -> HostList {
        var list = HostList(identifiers: [], capacity: 8)
        for line in lines {
            if line.hasPrefix("HID computers ("),
               let capacity = line.split(separator: " ").compactMap({ Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "():"))) }).last {
                list.capacity = capacity
            } else if !line.contains(" "), line.allSatisfy(\.isHexDigit) {
                list.identifiers.append(line)
            }
        }
        return list
    }
}

struct DeviceEvent: Identifiable, Sendable {
    let id: Int
    let uptime: Int
    let name: String
    let value: Int

    /// Parses `LOG ms=83368 event=finger_matched value=1`.
    static func parse(_ lines: [String]) -> [DeviceEvent] {
        lines.enumerated().compactMap { index, line in
            guard line.hasPrefix("LOG ") else { return nil }
            var fields: [String: String] = [:]
            for pair in line.dropFirst(4).split(separator: " ") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2 { fields[String(parts[0])] = String(parts[1]) }
            }
            guard let ms = fields["ms"].flatMap(Int.init), let name = fields["event"] else { return nil }
            return DeviceEvent(id: index, uptime: ms, name: name, value: Int(fields["value"] ?? "") ?? 0)
        }
        .reversed()
    }

    var title: String {
        switch name {
        case "finger_matched": "Finger \(fingerForTemplate) matched"
        case "finger_no_match": "No match"
        case "touch_detected": "Touch detected"
        case "hid_requested": "Password requested"
        case "hid_typed", "hid_sent": "Password typed"
        case "hid_failed": "Password request failed"
        case "usb_attached": "USB connected"
        case "sensor_probe_ok": "Sensor ready"
        case "task_started": "Device started"
        case "piv_visible": "Smart card visible"
        case "piv_hidden": "Smart card hidden"
        default: name.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var symbol: String {
        switch name {
        case "finger_matched": "checkmark.circle.fill"
        case "finger_no_match", "hid_failed": "xmark.circle.fill"
        case "touch_detected": "touchid"
        case let n where n.hasPrefix("hid_"): "key.fill"
        case let n where n.hasPrefix("usb_"): "cable.connector"
        case let n where n.hasPrefix("piv_"): "person.text.rectangle"
        default: "info.circle"
        }
    }

    var tint: Color {
        switch name {
        case "finger_matched": .green
        case "finger_no_match", "hid_failed": .red
        default: .secondary
        }
    }

    private var fingerForTemplate: Int { max(1, (value - 1) / 4 + 1) }

    var uptimeText: String {
        let seconds = uptime / 1000
        let duration = Duration.seconds(seconds)
        return duration.formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}

enum SettingTitles {
    static func title(for name: String) -> String {
        switch name {
        case "mode": "Mode"
        case "led": "Sensor lighting"
        case "piv_delay_ms": "PIN entry delay"
        case "typing_delay_ms": "Typing delay"
        case "submit_enter": "Press Return after typing"
        case "touch_cooldown_ms": "Touch cooldown"
        case "led_idle_color": "Idle color"
        case "led_success_color": "Success color"
        case "led_failure_color": "Failure color"
        case "led_idle_end_color": "Breathing end color"
        case "led_idle_effect": "Idle effect"
        case "led_idle_cycles": "Animation repeats"
        case "led_feedback_ms": "Result feedback duration"
        case "piv_auto_type": "Type PIN automatically"
        default: name.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
