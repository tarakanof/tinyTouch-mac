import SwiftUI

struct ComputersView: View {
    @Environment(DeviceStore.self) private var store
    @State private var pendingRemoval: String?

    var body: some View {
        Form {
            Section {
                if store.hosts.identifiers.isEmpty {
                    ContentUnavailableView {
                        Label("No Registered Computers", systemImage: "laptopcomputer.slash")
                    } description: {
                        Text("Password entry needs this Mac to be registered. Run HID setup to add it.")
                    } actions: {
                        Button("Set Up This Mac…") {
                            store.openInTerminal(["setup", "--mode", "hid", "--skip-enroll"])
                        }
                    }
                } else {
                    ForEach(store.hosts.identifiers, id: \.self) { identifier in
                        HStack(spacing: 12) {
                            Image(systemName: "laptopcomputer")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                                .frame(width: 28)
                            Text(identifier)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                            Spacer()
                            Button("Remove…", role: .destructive) {
                                pendingRemoval = identifier
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Password Entry Computers")
                    Spacer()
                    Text("\(store.hosts.identifiers.count) of \(store.hosts.capacity)")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Each Mac keeps its own password and pairing key in its login Keychain. To add another Mac, install tinytouch there and run HID setup.")
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
            Text(store.hosts.identifiers.count == 1
                 ? "It's the last registered computer, so tinyTouch switches to smart card mode."
                 : "That Mac can no longer receive passwords from tinyTouch until it runs setup again.")
        }
    }
}
