import SwiftUI

struct GeneralSettingsView: View {
    @Environment(DeviceStore.self) private var store
    @State private var draft = SettingsDraft(keys: [
        "typing_delay_ms", "submit_enter", "touch_cooldown_ms", "piv_delay_ms", "piv_auto_type",
    ])
    @State private var pendingMode: DeviceMode?
    @State private var pendingPIVTouch: Bool?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                deviceSection
                modeSection
                if store.status?.mode == .hid {
                    hidSection
                } else {
                    pivSection
                }
                Section("Touch") {
                    NumberSettingRow(
                        title: "Touch cooldown",
                        help: "Minimum time between two touch actions.",
                        value: draft.int("touch_cooldown_ms", in: range("touch_cooldown_ms")),
                        range: range("touch_cooldown_ms"),
                        step: 50
                    )
                }
            }
            .formStyle(.grouped)

            ApplyBar(changeCount: draft.changes.count, revert: draft.revert) {
                Task { _ = await store.apply(draft.changes) }
            }
        }
        .onAppear { draft.load(store.config) }
        .onChange(of: store.config) { draft.load(store.config) }
        .confirmationDialog(
            "Switch to \(pendingMode?.title ?? "")?",
            isPresented: Binding(get: { pendingMode != nil }, set: { if !$0 { pendingMode = nil } }),
            presenting: pendingMode
        ) { mode in
            Button("Switch Mode") { Task { await store.setMode(mode) } }
        } message: { mode in
            Text(modeMessage(mode))
        }
        .confirmationDialog(
            pendingPIVTouch == true ? "Turn on touch activation?" : "Turn off touch activation?",
            isPresented: Binding(get: { pendingPIVTouch != nil }, set: { if !$0 { pendingPIVTouch = nil } }),
            presenting: pendingPIVTouch
        ) { enabled in
            Button(enabled ? "Turn On" : "Turn Off") { Task { await store.setPIVTouch(enabled) } }
        } message: { _ in
            Text("You'll need to unplug and reconnect tinyTouch afterward.")
        }
    }

    private var deviceSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "touchid")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("tinyTouch").font(.title3.weight(.semibold))
                    ConnectionBadge()
                }
                Spacer()
                Button {
                    Task { await store.refreshAll() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .disabled(store.isBusy)
                .help("Read the device again")
            }
            if let status = store.status {
                LabeledContent("Firmware", value: "\(status.firmware) (\(status.build))")
                LabeledContent("Sensor") {
                    Label(status.sensorReady ? "Ready" : "Offline",
                          systemImage: status.sensorReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(status.sensorReady ? .green : .orange)
                }
                if status.ota != "idle" {
                    LabeledContent("Firmware update", value: status.ota == "staged" ? "Ready — reconnect to install" : "Writing…")
                }
            }
        }
    }

    private var modeSection: some View {
        Section {
            Picker("Mode", selection: Binding(
                get: { store.status?.mode ?? .piv },
                set: { if $0 != store.status?.mode { pendingMode = $0 } }
            )) {
                ForEach(DeviceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Authentication")
        } footer: {
            Text(store.status?.mode?.summary ?? "")
        }
    }

    private var hidSection: some View {
        Section("Password Entry") {
            LabeledContent("Background helper") {
                if store.helperRunning {
                    Label("Running", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Repair Helper") { Task { await store.repairHelper() } }
                }
            }
            Toggle(isOn: draft.bool("submit_enter")) {
                Text("Press Return after typing")
                Text("Submits the password field automatically.")
            }
            NumberSettingRow(
                title: "Typing delay",
                help: "Increase if a field drops characters.",
                value: draft.int("typing_delay_ms", in: range("typing_delay_ms")),
                range: range("typing_delay_ms")
            )
            Picker(selection: Binding(
                get: { store.keyboardLayout },
                set: { layout in Task { await store.setKeyboardLayout(layout) } }
            )) {
                Text("Match macOS input source").tag("auto")
                Text("U.S.").tag("us")
            } label: {
                Text("Keyboard layout")
                Text("Applies to this Mac only.")
            }
            LabeledContent("Password") {
                Button("Change Password…") { store.openInTerminal(["password"]) }
            }
        }
    }

    private var pivSection: some View {
        Section("Smart Card") {
            LabeledContent("Identity") {
                if store.status?.pivReady == true {
                    Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("Set Up…") { store.openInTerminal(["setup", "--mode", "piv", "--skip-enroll"]) }
                }
            }
            Toggle(isOn: draft.bool("piv_auto_type")) {
                Text("Type PIN automatically")
                Text("Enters the placeholder PIN after a fingerprint match.")
            }
            NumberSettingRow(
                title: "PIN entry delay",
                help: "Raise this if the PIN starts before the field is ready.",
                value: draft.int("piv_delay_ms", in: range("piv_delay_ms")),
                range: range("piv_delay_ms"),
                step: 25
            )
            Toggle(isOn: Binding(
                get: { store.status?.pivTouch ?? false },
                set: { pendingPIVTouch = $0 }
            )) {
                Text("Touch activation")
                Text("Hides the smart card until you touch the sensor, so password sign-in stays available.")
            }
        }
    }

    private func range(_ key: String) -> ClosedRange<Int> {
        store.catalog[key]?.range ?? 0...5000
    }

    private func modeMessage(_ mode: DeviceMode) -> String {
        var message = "You'll need to unplug and reconnect tinyTouch afterward."
        if mode == .hid, store.hosts.identifiers.isEmpty {
            message += " This Mac isn't registered for password entry yet — run setup after switching."
        }
        if mode == .piv, store.status?.pivReady != true {
            message += " The smart card identity isn't set up yet — run setup after switching."
        }
        return message
    }
}
