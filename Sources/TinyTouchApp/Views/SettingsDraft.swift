import SwiftUI

/// Local edits to device settings, saved together with one approval per change.
@MainActor
@Observable
final class SettingsDraft {
    let keys: [String]
    private(set) var saved: [String: String] = [:]
    var values: [String: String] = [:]

    init(keys: [String]) {
        self.keys = keys
    }

    func load(_ config: [String: String]) {
        let changed = Set(changes.map(\.name))
        saved = config.filter { keys.contains($0.key) }
        for key in keys where !changed.contains(key) {
            values[key] = config[key]
        }
    }

    var changes: [(name: String, value: String)] {
        keys.compactMap { key in
            guard let value = values[key], value != saved[key] else { return nil }
            return (key, value)
        }
    }

    func revert() {
        values = saved
    }

    func string(_ key: String) -> Binding<String> {
        Binding(
            get: { self.values[key] ?? "" },
            set: { self.values[key] = $0 }
        )
    }

    func bool(_ key: String) -> Binding<Bool> {
        Binding(
            get: { ["on", "1"].contains(self.values[key] ?? "") },
            set: { self.values[key] = $0 ? "on" : "off" }
        )
    }

    func int(_ key: String, in range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { Int(self.values[key] ?? "") ?? range.lowerBound },
            set: { self.values[key] = String(min(max($0, range.lowerBound), range.upperBound)) }
        )
    }
}

struct NumberSettingRow: View {
    let title: String
    var help: String?
    var unit = "ms"
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                TextField(title, value: $value, format: .number.grouping(.never))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                Text(unit)
                    .foregroundStyle(.secondary)
                Stepper(title, value: $value, in: range, step: step)
                    .labelsHidden()
            }
        } label: {
            Text(title)
            if let help {
                Text(help)
            }
        }
    }
}
