import SwiftUI

struct ActivityView: View {
    @Environment(DeviceStore.self) private var store
    @State private var category = DeviceEvent.Category.all
    @State private var search = ""

    var body: some View {
        let entries = filtered
        Form {
            Section {
                if entries.isEmpty {
                    Text(store.events.isEmpty ? "No recent events." : "No matching events.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        ActivityRow(entry: entry)
                    }
                }
            } header: {
                Picker("Show", selection: $category) {
                    ForEach(DeviceEvent.Category.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .frame(maxWidth: .infinity)
            } footer: {
                Text("The last 32 events stored on tinyTouch, with a touch and what it led to on one row. Times count from when tinyTouch started.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .searchable(text: $search, placement: .toolbarPrincipal, prompt: "Search activity")
        .task(id: store.port) { await store.refreshLogs() }
        .motion(.smooth(duration: 0.3), value: category)
        .motion(.smooth(duration: 0.3), value: entries.map(\.id))
    }

    private var filtered: [ActivityEntry] {
        ActivityEntry.group(store.events).filter { entry in
            entry.belongs(to: category) && (search.isEmpty || entry.matches(search))
        }
    }
}

/// One touch or device event: what happened, which finger, the steps and when.
struct ActivityRow: View {
    @Environment(AppPreferences.self) private var preferences
    let entry: ActivityEntry
    var showsSteps = true

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            OutcomeGlyph(symbol: entry.symbol, tint: entry.tint)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(entry.title)
                        .fontWeight(.medium)
                    if let finger = entry.finger {
                        Text("· \(preferences.fingerName(finger))")
                            .foregroundStyle(.secondary)
                    }
                }
                if showsSteps, !entry.steps.isEmpty {
                    Text(entry.steps.joined(separator: "  ›  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 3)
            Spacer(minLength: 8)
            Text(entry.uptimeText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.top, 5)
        }
        .accessibilityElement(children: .combine)
    }
}
