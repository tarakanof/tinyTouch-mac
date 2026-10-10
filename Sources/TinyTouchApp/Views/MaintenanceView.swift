import SwiftUI

struct MaintenanceView: View {
    @Environment(DeviceStore.self) private var store
    @State private var confirmReset = false
    @State private var confirmUninstall = false

    var body: some View {
        Form {
            Section("Software") {
                LabeledContent("tinytouch CLI", value: store.cliVersion.isEmpty ? "—" : store.cliVersion)
                LabeledContent("Firmware", value: store.status?.firmware ?? "—")
                LabeledContent {
                    Button("Update…") { store.openInTerminal(["update"]) }
                } label: {
                    Text("Check for updates")
                    Text("Updates the CLI, helper, and firmware in Terminal.")
                }
            }

            Section("Connection") {
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
                LabeledContent("HID helper") {
                    HStack {
                        Text(store.helperRunning ? "Running" : "Not running")
                            .foregroundStyle(.secondary)
                        Button("Repair") { Task { await store.repairHelper() } }
                        Button("Remove…") { confirmUninstall = true }
                            .disabled(!store.helperRunning)
                    }
                }
                LabeledContent {
                    Button("Run Setup…") { store.openInTerminal(["setup"]) }
                } label: {
                    Text("Setup")
                    Text("Registers this Mac and pairs the smart card identity.")
                }
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
                                .frame(width: 20)
                            Text(event.title)
                            Spacer()
                            Text(event.uptimeText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .help("Time since the device started")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Recent Activity")
                    Spacer()
                    Button {
                        Task { await store.refreshLogs() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(store.port == nil || store.isBusy)
                }
            }

            Section {
                LabeledContent {
                    Button("Factory Reset…", role: .destructive) { confirmReset = true }
                        .disabled(store.port == nil)
                } label: {
                    Text("Factory reset")
                    Text("Erases fingerprints, keys, registered computers, and settings.")
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
