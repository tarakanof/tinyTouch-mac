import SwiftUI

struct ComputersView: View {
    @Environment(DeviceStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @State private var pendingRemoval: String?
    @State private var renaming: String?
    @State private var newName = ""

    private var hosts: HostList { store.hosts ?? HostList(identifiers: [], capacity: 8) }

    var body: some View {
        Form {
            Section {
                if store.hosts == nil {
                    if store.hostsReadFailed {
                        LabeledContent("Couldn't read the list from tinyTouch.") {
                            Button("Try Again") { Task { await store.refreshHosts() } }
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading…").foregroundStyle(.secondary)
                        }
                    }
                } else if hosts.identifiers.isEmpty {
                    ContentUnavailableView {
                        Label("No Registered Computers", systemImage: "laptopcomputer.slash")
                    } description: {
                        Text("Run password entry setup to register this Mac.")
                    } actions: {
                        Button("Set Up This Mac…") {
                            store.setupRequest = .hid
                        }
                    }
                } else {
                    ForEach(hosts.identifiers, id: \.self) { identifier in
                        let isLocal = identifier == hosts.local
                        HStack(spacing: 10) {
                            SettingIcon(symbol: "laptopcomputer", color: isLocal ? .blue : .gray, size: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name(identifier, isLocal: isLocal))
                                Text(isLocal ? "This Mac" : "ID \(identifier.prefix(8))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .help(identifier)
                            }
                            Spacer()
                            Button("Rename…") {
                                newName = preferences.computerName(identifier) ?? ""
                                renaming = identifier
                            }
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                pendingRemoval = identifier
                            }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.red)
                            .help("Remove this computer")
                        }
                    }
                }
            } header: {
                SectionHeader(title: "Password Entry Computers") {
                    if let hosts = store.hosts {
                        Text("\(hosts.identifiers.count) of \(hosts.capacity)")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Each Mac keeps its own password and pairing key in its login Keychain. To add another Mac, install tinyTouch there and run setup. Names are kept on this Mac.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .task(id: store.port) { await store.refreshHosts() }
        .alert(
            "Rename this computer",
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
            presenting: renaming
        ) { identifier in
            TextField("Name", text: $newName)
            Button("Save") { preferences.setComputerName(newName, for: identifier) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("For example, Office iMac. Leave it empty to remove the name.")
        }
        .confirmationDialog(
            "Remove this computer?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { identifier in
            Button("Remove", role: .destructive) {
                Task { await store.removeHost(identifier) }
            }
        } message: { _ in
            Text(hosts.identifiers.count == 1
                 ? "It's the last registered computer, so tinyTouch switches to smart card mode."
                 : "That Mac can no longer receive passwords from tinyTouch until it runs setup again.")
        }
    }

    private func name(_ identifier: String, isLocal: Bool) -> String {
        preferences.computerName(identifier)
            ?? (isLocal ? (Host.current().localizedName ?? "This Mac") : "Another Mac")
    }
}
