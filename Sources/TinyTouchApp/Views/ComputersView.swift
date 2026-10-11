import SwiftUI

struct ComputersView: View {
    @Environment(DeviceStore.self) private var store
    @State private var pendingRemoval: String?

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
                            SettingIcon(symbol: "laptopcomputer", color: isLocal ? .blue : .gray)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isLocal ? (Host.current().localizedName ?? "This Mac") : "Another Mac")
                                Text(isLocal ? "This Mac" : "ID \(identifier.prefix(8))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .help(identifier)
                            }
                            Spacer()
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
                Text("Each Mac keeps its own password and pairing key in its login Keychain. To add another Mac, install tinyTouch there and run setup.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .task(id: store.port) { await store.refreshHosts() }
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
}
