import SwiftUI

struct ActivityView: View {
    @Environment(DeviceStore.self) private var store
    @State private var category = DeviceEvent.Category.all
    @State private var search = ""

    var body: some View {
        Form {
            Section {
                if filtered.isEmpty {
                    Text(store.events.isEmpty ? "No recent events." : "No matching events.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { event in
                        HStack(spacing: 10) {
                            Image(systemName: event.symbol)
                                .foregroundStyle(event.tint)
                                .frame(width: 22)
                            Text(event.title)
                            Spacer()
                            Text(event.uptimeText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
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
                Text("The last 32 events stored on tinyTouch. Times count from when it started.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .searchable(text: $search, placement: .toolbarPrincipal, prompt: "Search activity")
        .task(id: store.port) { await store.refreshLogs() }
    }

    private var filtered: [DeviceEvent] {
        store.events.filter { event in
            event.belongs(to: category)
                && (search.isEmpty || event.title.localizedCaseInsensitiveContains(search))
        }
    }
}
