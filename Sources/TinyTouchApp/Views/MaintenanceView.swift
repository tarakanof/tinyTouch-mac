import SwiftUI

struct MaintenanceView: View {
    @Environment(DeviceStore.self) private var store
    @State private var confirmReset = false
    @State private var confirmUninstall = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(store.cliVersion.isEmpty ? "—" : store.cliVersion).foregroundStyle(.secondary)
                } label: {
                    SettingLabel(
                        title: "tinytouch CLI",
                        symbol: "terminal.fill",
                        color: .gray,
                        info: store.cli.map { $0.isBundled ? "Built into this app." : "Using \($0.executable.path)." }
                    )
                }
                LabeledContent {
                    Text(store.status?.firmware ?? "—").foregroundStyle(.secondary)
                } label: {
                    SettingLabel(title: "Firmware", symbol: "memorychip.fill", color: .gray)
                }
            } header: {
                SectionHeader("Software")
            }

            Section {
                LabeledContent {
                    Picker("Device port", selection: Binding(
                        get: { store.port ?? store.preferredPort ?? "" },
                        set: { port in
                            store.preferredPort = port
                            Task { await store.refreshAll() }
                        }
                    )) {
                        if store.availablePorts.isEmpty {
                            Text("None").tag("")
                        }
                        ForEach(store.availablePorts, id: \.self) { port in
                            Text(port.replacingOccurrences(of: "/dev/cu.", with: "")).tag(port)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    SettingLabel(title: "Device port", symbol: "cable.connector", color: .gray)
                }
                LabeledContent {
                    HStack {
                        StatusBadge(
                            text: store.helperRunning ? "Running" : "Not running",
                            color: store.helperRunning ? .green : .secondary
                        )
                        Button("Repair") { Task { await store.repairHelper() } }
                        Button("Remove", systemImage: "trash", role: .destructive) { confirmUninstall = true }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.red)
                            .disabled(!store.helperRunning)
                            .help("Remove the HID helper")
                    }
                } label: {
                    SettingLabel(
                        title: "HID helper",
                        symbol: "gearshape.2.fill",
                        color: .gray,
                        info: "Repair reinstalls the helper and re-authorizes Keychain access. Saved passwords are kept."
                            + (store.helperExecutable.map { "\n\nRuns \($0)." } ?? "")
                    )
                }
                LabeledContent {
                    Button("Run Setup…") { store.setupRequest = .some(nil) }
                } label: {
                    SettingLabel(
                        title: "Setup",
                        symbol: "wand.and.stars",
                        color: .purple,
                        info: "Registers this Mac for password entry or pairs the smart card identity."
                    )
                }
            } header: {
                SectionHeader("Connection")
            }

            Section {
                if store.events.isEmpty {
                    Text("No recent events.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.events) { event in
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
                SectionHeader(
                    title: "Recent Activity",
                    help: "The last 32 events stored on the device. Times count from when the device started."
                ) {
                    RefreshButton { await store.refreshLogs() }
                }
            }

            Section {
                LabeledContent {
                    Button("Reset…", role: .destructive) { confirmReset = true }
                        .disabled(store.port == nil)
                } label: {
                    SettingLabel(
                        title: "Factory reset",
                        symbol: "exclamationmark.triangle.fill",
                        color: .red,
                        info: "Erases fingerprints, keys, registered computers and settings on the device."
                    )
                }
            }
        }
        .formStyle(.grouped)
        .task(id: store.port) {
            await store.refreshHelper()
            await store.refreshLogs()
        }
        .confirmationDialog("Factory reset tinyTouch?", isPresented: $confirmReset) {
            Button("Erase Everything", role: .destructive) {
                Task { await store.factoryReset() }
            }
        } message: {
            Text("All fingerprints, keys, registered computers, and settings are erased, along with this Mac's saved password for the device. You'll approve with a fingerprint, then need to run setup again.")
        }
        .confirmationDialog("Remove the HID helper?", isPresented: $confirmUninstall) {
            Button("Remove", role: .destructive) {
                Task { await store.uninstallHelper() }
            }
        } message: {
            Text("Password entry stops working on this Mac until you repair or reinstall the helper. Saved credentials are kept.")
        }
    }
}
