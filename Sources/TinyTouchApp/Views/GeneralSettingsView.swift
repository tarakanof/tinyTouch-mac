import SwiftUI

struct GeneralSettingsView: View {
    @Environment(DeviceStore.self) private var store
    @State private var draft = SettingsDraft(keys: [
        "typing_delay_ms", "submit_enter", "touch_cooldown_ms", "piv_delay_ms", "piv_auto_type",
    ])
    @State private var pendingMode: DeviceMode?
    @State private var pendingPIVTouch: Bool?
    @State private var changingPassword = false

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
                Section {
                    NumberSettingRow(
                        title: "Touch cooldown",
                        symbol: "hourglass",
                        color: .pink,
                        info: "Minimum time between two touch actions, so one long touch doesn't trigger twice.",
                        value: draft.int("touch_cooldown_ms", in: range("touch_cooldown_ms")),
                        range: range("touch_cooldown_ms"),
                        step: 50
                    )
                } header: {
                    SectionHeader("Touch")
                }
            }
            .formStyle(.grouped)

            ApplyBar(changeCount: draft.changes.count, revert: draft.revert) {
                Task { _ = await store.apply(draft.changes) }
            }
        }
        .onAppear { draft.load(store.config) }
        .onChange(of: store.config) { draft.load(store.config) }
        .sheet(isPresented: $changingPassword) { ChangePasswordSheet() }
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
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom),
                        in: .rect(cornerRadius: 12)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("tinyTouch").font(.title3.weight(.semibold))
                    ConnectionBadge()
                }
                Spacer()
            }
            if let status = store.status {
                LabeledContent {
                    Text("\(status.firmware) (\(status.build))")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } label: {
                    SettingLabel(title: "Firmware", symbol: "memorychip.fill", color: .gray)
                }
                LabeledContent {
                    StatusBadge(
                        text: status.sensorReady ? "Ready" : "Offline",
                        color: status.sensorReady ? .green : .orange
                    )
                } label: {
                    SettingLabel(title: "Sensor", symbol: "touchid", color: .green)
                }
                if status.ota != "idle" {
                    LabeledContent {
                        StatusBadge(text: status.ota == "staged" ? "Reconnect to install" : "Writing…", color: .blue)
                    } label: {
                        SettingLabel(title: "Firmware update", symbol: "arrow.down.circle.fill", color: .blue)
                    }
                }
            }
        }
    }

    private var modeSection: some View {
        Section {
            Picker(selection: Binding(
                get: { store.status?.mode ?? .piv },
                set: { if $0 != store.status?.mode { pendingMode = $0 } }
            )) {
                ForEach(DeviceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                SettingLabel(title: "Mode", symbol: "lock.shield.fill", color: .blue)
            }
            .pickerStyle(.segmented)
        } header: {
            SectionHeader(
                "Authentication",
                help: "\(DeviceMode.hid.title): \(DeviceMode.hid.summary)\n\n\(DeviceMode.piv.title): \(DeviceMode.piv.summary)"
            )
        }
    }

    private var hidSection: some View {
        Section {
            LabeledContent {
                if store.helperRunning {
                    StatusBadge(text: "Running", color: .green)
                } else {
                    Button("Repair") { Task { await store.repairHelper() } }
                }
            } label: {
                SettingLabel(
                    title: "Background helper",
                    symbol: "gearshape.2.fill",
                    color: .gray,
                    info: "Keeps your password in the login Keychain and hands it to tinyTouch, encrypted, after a fingerprint match."
                )
            }
            ToggleRow(
                title: "Press Return after typing",
                symbol: "return",
                color: .blue,
                info: "Submits the password field automatically after the password is typed.",
                isOn: draft.bool("submit_enter")
            )
            NumberSettingRow(
                title: "Typing delay",
                symbol: "keyboard.fill",
                color: .indigo,
                info: "Pause after each key press. Increase it if a password field drops characters.",
                value: draft.int("typing_delay_ms", in: range("typing_delay_ms")),
                range: range("typing_delay_ms")
            )
            LabeledContent {
                Picker("Keyboard layout", selection: Binding(
                    get: { store.keyboardLayout },
                    set: { layout in Task { await store.setKeyboardLayout(layout) } }
                )) {
                    Text("Match Input Source").tag("auto")
                    Text("U.S.").tag("us")
                }
                .labelsHidden()
                .fixedSize()
            } label: {
                SettingLabel(
                    title: "Keyboard layout",
                    symbol: "globe",
                    color: .teal,
                    info: "How your password is translated into key presses. Applies to this Mac only and doesn't need a touch."
                )
            }
            LabeledContent {
                Button("Change…") { changingPassword = true }
            } label: {
                SettingLabel(
                    title: "Password",
                    symbol: "key.fill",
                    color: .orange,
                    info: "Changes the password tinyTouch types. Fingerprints and pairing are kept."
                )
            }
        } header: {
            SectionHeader("Password Entry")
        }
    }

    private var pivSection: some View {
        Section {
            LabeledContent {
                if store.status?.pivReady == true {
                    StatusBadge(text: "Ready", color: .green)
                } else {
                    Button("Set Up…") { store.setupRequest = .piv }
                }
            } label: {
                SettingLabel(title: "Identity", symbol: "person.text.rectangle.fill", color: .blue)
            }
            ToggleRow(
                title: "Type PIN automatically",
                symbol: "ellipsis.rectangle.fill",
                color: .indigo,
                info: "Enters the placeholder PIN after a fingerprint match. When off, type 111111 yourself.",
                isOn: draft.bool("piv_auto_type")
            )
            NumberSettingRow(
                title: "PIN entry delay",
                symbol: "timer",
                color: .orange,
                info: "Wait before typing the PIN. Raise it if typing starts before the PIN field is ready.",
                value: draft.int("piv_delay_ms", in: range("piv_delay_ms")),
                range: range("piv_delay_ms"),
                step: 25
            )
            ToggleRow(
                title: "Touch activation",
                symbol: "hand.tap.fill",
                color: .purple,
                info: "Hides the smart card until you touch the sensor, so password sign-in stays available. Requires reconnecting.",
                isOn: Binding(
                    get: { store.status?.pivTouch ?? false },
                    set: { pendingPIVTouch = $0 }
                )
            )
        } header: {
            SectionHeader("Smart Card")
        }
    }

    private func range(_ key: String) -> ClosedRange<Int> {
        store.catalog[key]?.range ?? 0...5000
    }

    private func modeMessage(_ mode: DeviceMode) -> String {
        var message = "You'll need to unplug and reconnect tinyTouch afterward."
        if mode == .hid, store.status?.hosts == 0 {
            message += " This Mac isn't registered for password entry yet — run setup after switching."
        }
        if mode == .piv, store.status?.pivReady != true {
            message += " The smart card identity isn't set up yet — run setup after switching."
        }
        return message
    }
}
