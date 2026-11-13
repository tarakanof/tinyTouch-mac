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
    var sensorReady: Bool { ["ready", "ok"].contains(raw["sensor"]) }
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

extension LEDColor {
    /// The colour of the lit ring; nil when the ring is dark.
    var light: Color? { self == .off ? nil : swatch }
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

    /// What `tinytouch led preset` writes; mirrors `LED_PRESETS` in the CLI. Staging
    /// these saves a theme together with the other lighting edits.
    var settings: [String: String] {
        let (idle, end, success, failure, effect): (LEDColor, LEDColor, LEDColor, LEDColor, LEDEffect) = switch self {
        case .default: (.blue, .blue, .green, .red, .steady)
        case .ocean: (.blue, .cyan, .cyan, .red, .breathe)
        case .neon: (.purple, .cyan, .green, .red, .breathe)
        case .sunset: (.red, .yellow, .yellow, .purple, .breathe)
        }
        return [
            "led_idle_color": idle.rawValue, "led_idle_end_color": end.rawValue,
            "led_success_color": success.rawValue, "led_failure_color": failure.rawValue,
            "led_idle_effect": effect.rawValue, "led_idle_cycles": "0",
        ]
    }
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
    var local: String?

    /// Parses `tinytouch computers`, e.g. "HID computers (1 of 8):" followed by IDs,
    /// with "(this Mac)" after the ID whose pairing key is in this Mac's Keychain.
    static func parse(_ lines: [String]) -> HostList {
        var list = HostList(identifiers: [], capacity: 8)
        for line in lines {
            let words = line.split(separator: " ")
            if line.hasPrefix("HID computers ("),
               let capacity = words.compactMap({ Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "():"))) }).last {
                list.capacity = capacity
            } else if let first = words.first, first.allSatisfy(\.isHexDigit) {
                let identifier = String(first)
                list.identifiers.append(identifier)
                if line.hasSuffix("(this Mac)") { list.local = identifier }
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
        case "hid_typing": "Typing password"
        case "hid_response": "Helper replied"
        case "hid_failed": "Password request failed"
        case "usb_attached": "USB connected"
        case "sensor_probe_ok": "Sensor ready"
        case "task_started": "Device started"
        case "piv_visible": "Smart card visible"
        case "piv_hidden": "Smart card hidden"
        case "piv_pin_typed": "PIN typed"
        case "piv_pin_failed": "PIN entry failed"
        case "piv_presence_granted": "Smart card unlocked"
        case "piv_crypto_ok": "Smart card key used"
        case "piv_crypto_rejected": "Smart card key refused"
        case "piv_discovery_timeout": "Smart card wasn't picked up"
        case "finger_capture_cancelled": "Touch too short"
        case "sensor_probe_failed": "Sensor not responding"
        case "sensor_recovered": "Sensor recovered"
        case "sensor_recover_failed": "Sensor recovery failed"
        default: name.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Events whose value is the matched fingerprint template. Other events use the
    /// value for something else: `piv_crypto_ok` logs the smart card key it used.
    private static let namesWithATemplate: Set<String> = [
        "finger_matched", "hid_requested", "hid_typing", "hid_typed", "hid_failed",
        "piv_presence_granted", "piv_discovery_timeout", "piv_pin_typed", "piv_pin_failed",
    ]

    /// The finger this event is about, when the device recorded one.
    var finger: Int? {
        Self.namesWithATemplate.contains(name) && value > 0 ? fingerForTemplate : nil
    }

    var isProblem: Bool {
        name == "finger_no_match" || name.hasSuffix("_failed") || name.hasSuffix("_error")
            || name.hasSuffix("_rejected") || name.hasSuffix("_timeout")
    }

    /// True for what a touch sets off: the match, then password or smart card work.
    var followsTouch: Bool {
        (name.hasPrefix("finger_") || name.hasPrefix("hid_") || name.hasPrefix("piv_"))
            && name != "piv_hidden"
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

    enum Category: String, CaseIterable, Identifiable {
        case all, fingerprints, passwords, problems, device

        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "All"
            case .fingerprints: "Fingerprints"
            case .passwords: "Passwords"
            case .problems: "Problems"
            case .device: "Device"
            }
        }
    }

    func belongs(to category: Category) -> Bool {
        switch category {
        case .all: true
        case .fingerprints: name.hasPrefix("finger_") || name == "touch_detected"
        case .passwords: name.hasPrefix("hid_")
        case .problems: isProblem
        case .device: !name.hasPrefix("finger_") && !name.hasPrefix("hid_") && name != "touch_detected"
        }
    }

    private var fingerForTemplate: Int { max(1, (value - 1) / 4 + 1) }

    var uptimeText: String {
        let seconds = uptime / 1000
        let duration = Duration.seconds(seconds)
        return duration.formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}

/// One row in Activity: a touch with everything it led to, or a single device event.
struct ActivityEntry: Identifiable, Sendable {
    /// Oldest first.
    let events: [DeviceEvent]

    var id: Int { events[0].id }
    var uptimeText: String { events[0].uptimeText }
    var finger: Int? { events.lazy.compactMap(\.finger).first }
    var isProblem: Bool { events.contains(where: \.isProblem) }

    /// The most telling event: a failure first, then how far the touch got.
    private var headline: DeviceEvent {
        let order = [
            "hid_failed", "piv_pin_failed", "piv_crypto_rejected", "piv_discovery_timeout",
            "hid_typed", "hid_sent", "piv_pin_typed", "piv_crypto_ok", "piv_presence_granted",
            "finger_no_match", "finger_matched", "finger_capture_cancelled",
        ]
        for name in order {
            if let event = events.first(where: { $0.name == name }) { return event }
        }
        return events[0]
    }

    var title: String {
        headline.name == "finger_matched" ? "Finger matched" : headline.title
    }

    var symbol: String { events.count > 1 || headline.followsTouch ? outcomeSymbol : headline.symbol }
    var tint: Color { isProblem ? .red : (succeeded ? .green : .secondary) }

    private var succeeded: Bool {
        ["hid_typed", "hid_sent", "piv_pin_typed", "piv_crypto_ok", "piv_presence_granted", "finger_matched"]
            .contains(headline.name)
    }

    private var outcomeSymbol: String {
        isProblem ? "xmark" : (succeeded ? "checkmark" : "touchid")
    }

    /// What happened in order, shown only when a touch led to more than one event.
    var steps: [String] {
        guard events.count > 1 else { return [] }
        var steps = events.map(\.title)
        if let first = events.first, let last = events.last, last.uptime > first.uptime {
            let seconds = Double(last.uptime - first.uptime) / 1000
            steps.append(seconds.formatted(.number.precision(.fractionLength(1))) + " s")
        }
        return steps
    }

    func belongs(to category: DeviceEvent.Category) -> Bool {
        events.contains { $0.belongs(to: category) }
    }

    func matches(_ search: String) -> Bool {
        title.localizedCaseInsensitiveContains(search)
            || events.contains { $0.title.localizedCaseInsensitiveContains(search) }
    }

    /// How long after a touch its follow-up events still belong to it.
    private static let window = 15_000

    /// Folds a newest-first event list into rows, newest first. A touch and the
    /// match, password or smart card events that follow it become one row.
    static func group(_ events: [DeviceEvent]) -> [ActivityEntry] {
        var groups: [[DeviceEvent]] = []
        var open = false
        for event in events.reversed() {
            if event.name != "touch_detected", event.followsTouch, open, let start = groups.last?.first,
               event.uptime >= start.uptime, event.uptime - start.uptime <= window {
                groups[groups.count - 1].append(event)
            } else {
                groups.append([event])
                open = event.followsTouch || event.name == "touch_detected"
            }
        }
        return groups.reversed().map(ActivityEntry.init)
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
