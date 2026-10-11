import SwiftUI

struct MenuBarView: View {
    @Environment(DeviceStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let prompt = store.touchPrompt {
                TouchPromptCard(prompt: prompt)
            } else if store.enrollment != nil {
                Label("Enrollment in progress", systemImage: "touchid")
                    .foregroundStyle(.secondary)
            }

            if let status = store.status {
                if !MenuItem.status.filter(preferences.shows).isEmpty {
                    details(status)
                }
            } else {
                DisconnectedMessage()
            }

            Divider()

            VStack(spacing: 2) {
                MenuRow(title: "Open tinyTouch", symbol: "macwindow", shortcut: "o") {
                    show(nil)
                }
                if preferences.shows(.fingerprintsShortcut) {
                    MenuRow(title: "Fingerprints…", symbol: "touchid") {
                        show(.fingers)
                    }
                    .disabled(store.port == nil)
                }
                if preferences.shows(.activityShortcut) {
                    MenuRow(title: "Activity…", symbol: "list.bullet.rectangle") {
                        show(.activity)
                    }
                    .disabled(store.port == nil)
                }
                if preferences.shows(.refresh) {
                    MenuRow(title: "Refresh", symbol: "arrow.clockwise", closesMenu: false) {
                        Task { await store.refreshAll() }
                    }
                    .disabled(store.isBusy)
                }
                MenuRow(title: "Settings…", symbol: "gearshape", shortcut: ",") {
                    show(.app)
                }
            }

            Divider()

            MenuRow(title: "Quit tinyTouch", symbol: "power", shortcut: "q") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 250)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "touchid")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("tinyTouch")
                    .font(.headline)
                ConnectionBadge()
            }
            Spacer()
            if store.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func details(_ status: DeviceStatus) -> some View {
        VStack(spacing: 6) {
            if preferences.shows(.mode) {
                DetailRow(title: "Mode", value: status.mode?.title ?? "Unknown")
            }
            if preferences.shows(.fingerprints) {
                DetailRow(
                    title: "Fingerprints",
                    value: store.fingers.enrolledCount == 1 ? "1 finger" : "\(store.fingers.enrolledCount) fingers"
                )
            }
            if preferences.shows(.helper) {
                if status.mode == .hid {
                    DetailRow(title: "HID helper", value: store.helperRunning ? "Running" : "Not running",
                              warning: !store.helperRunning)
                } else {
                    DetailRow(title: "Smart card", value: status.pivReady ? "Ready" : "Not configured",
                              warning: !status.pivReady)
                }
            }
            if preferences.shows(.firmware) {
                DetailRow(title: "Firmware", value: status.firmware)
            }
            if preferences.shows(.port), let port = store.port {
                DetailRow(title: "Port", value: port.replacingOccurrences(of: "/dev/cu.", with: ""))
            }
        }
        .font(.callout)
    }

    private func show(_ tab: SettingsTab?) {
        if let tab { store.settingsTab = tab }
        openWindow(id: AppDelegate.mainWindow)
        NSApp.activate()
    }
}

private struct DetailRow: View {
    let title: String
    let value: String
    var warning = false

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            if warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .imageScale(.small)
            }
            Text(value)
        }
    }
}

private struct MenuRow: View {
    let title: String
    let symbol: String
    var shortcut: KeyEquivalent?
    var closesMenu = true
    let action: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hovering = false

    var body: some View {
        Button {
            if closesMenu { dismiss() }
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 18)
                Text(title)
                Spacer()
                if let shortcut {
                    Text("⌘\(String(shortcut.character).uppercased())")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(.rect)
            .background(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .modifier(OptionalShortcut(key: shortcut))
    }
}

private struct OptionalShortcut: ViewModifier {
    let key: KeyEquivalent?

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: .command)
        } else {
            content
        }
    }
}

struct ConnectionBadge: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var text: String {
        switch store.connection {
        case .noCLI: "CLI not installed"
        case .searching: "Looking for device…"
        case .disconnected: "Not connected"
        case .connected(let port): "Connected · \(port.replacingOccurrences(of: "/dev/cu.", with: ""))"
        case .failed: "Connection error"
        }
    }

    private var color: Color {
        switch store.connection {
        case .connected: .green
        case .searching: .yellow
        default: .secondary
        }
    }
}

struct DisconnectedMessage: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        switch store.connection {
        case .noCLI:
            ContentUnavailableView {
                Label("tinyTouch is incomplete", systemImage: "terminal")
            } description: {
                Text("The command-line tool inside the app is missing. Reinstall tinyTouch.")
            } actions: {
                Button("Check Again") {
                    Task { await store.relocateCLI() }
                }
            }
        case .failed(let message):
            ContentUnavailableView("Can't reach tinyTouch", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
        case .searching:
            ContentUnavailableView("Looking for tinyTouch…", systemImage: "cable.connector")
        default:
            ContentUnavailableView("tinyTouch isn't connected", systemImage: "cable.connector.slash",
                                   description: Text("Connect it with a USB data cable."))
        }
    }
}
