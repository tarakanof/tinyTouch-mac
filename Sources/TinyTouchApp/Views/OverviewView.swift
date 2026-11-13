import SwiftUI

/// The landing tab: the device as it is right now, anything that needs attention,
/// and the latest activity.
struct OverviewView: View {
    @Environment(DeviceStore.self) private var store
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                if let status = store.status {
                    stats(status)
                    ForEach(notices(status)) { notice in
                        NoticeBanner(notice: notice)
                            .transition(.blurReplace)
                    }
                    recent
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(alignment: .topLeading) { glow }
        // The log is read once per visit; each device command pauses password entry.
        .task(id: store.port) { await store.refreshLogs() }
        .motion(.smooth(duration: 0.35), value: store.status != nil)
    }

    /// The ring's light spilling behind the page and under the sidebar.
    private var glow: some View {
        RadialGradient(
            colors: [(store.idleLight.color ?? .clear).opacity(0.24), .clear],
            center: .topLeading, startRadius: 0, endRadius: 460
        )
        .frame(height: 460)
        .backgroundExtensionEffect()
        .motion(.smooth(duration: 0.6), value: store.idleLight)
        .accessibilityHidden(true)
    }

    private var hero: some View {
        HStack(spacing: 22) {
            SensorView(light: store.idleLight, size: 116)
            VStack(alignment: .leading, spacing: 4) {
                Text("tinyTouch")
                    .font(.largeTitle.weight(.bold))
                Text(headline)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.interpolate)
                if let status = store.status {
                    HStack(spacing: 6) {
                        StatusBadge(
                            text: status.sensorReady ? "Sensor ready" : "Sensor offline",
                            color: status.sensorReady ? .green : .orange,
                            symbol: status.sensorReady ? "checkmark" : "exclamationmark.triangle.fill"
                        )
                        if let mode = status.mode {
                            StatusBadge(text: mode.shortTitle, color: .blue)
                        }
                        StatusBadge(text: "Firmware \(status.firmware)", color: .secondary)
                            .help("Build \(status.build)")
                    }
                    .padding(.top, 6)
                } else if store.connection == .noCLI || isFailed {
                    Button(store.connection == .noCLI ? "Check Again" : "Try Again") {
                        Task {
                            if store.connection == .noCLI { await store.relocateCLI() } else { await store.refreshAll() }
                        }
                    }
                    .padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    private var isFailed: Bool {
        if case .failed = store.connection { return true }
        return false
    }

    private var headline: String {
        switch store.connection {
        case .noCLI:
            return "The command-line tool inside the app is missing. Reinstall tinyTouch."
        case .searching:
            return "Looking for tinyTouch…"
        case .disconnected:
            return "Not connected. Plug it in with a USB data cable."
        case .failed(let message):
            return message
        case .connected:
            guard let status = store.status else { return "Connecting…" }
            if !status.sensorReady { return "The fingerprint sensor isn't responding." }
            if store.fingers.enrolledCount == 0 { return "Add a fingerprint to start signing in." }
            if !store.isConfigured { return "Setup isn't finished on this Mac." }
            return "Ready. Touch the sensor to sign in."
        }
    }

    // MARK: - Stats

    private func stats(_ status: DeviceStatus) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 10)], spacing: 10) {
            StatTile(title: "Fingerprints", value: "\(store.fingers.enrolledCount)", unit: "of 10", tab: .fingers)
            StatTile(
                title: "Last match",
                value: store.lastMatchedFinger.map(preferences.fingerName) ?? "None yet",
                tab: .activity
            )
            if status.mode == .hid {
                StatTile(
                    title: "Background helper",
                    value: store.helperRunning ? "Running" : "Stopped",
                    tint: store.helperRunning ? .green : .orange,
                    tab: .signIn
                )
                StatTile(title: "Computers", value: "\(status.hosts)", unit: "of \(store.hosts?.capacity ?? 8)", tab: .computers)
            } else {
                StatTile(
                    title: "Smart card",
                    value: status.pivReady ? "Ready" : "Not set up",
                    tint: status.pivReady ? .green : .orange,
                    tab: .signIn
                )
            }
        }
    }

    // MARK: - Notices

    private func notices(_ status: DeviceStatus) -> [Notice] {
        var notices: [Notice] = []
        if status.ota == "staged" {
            notices.append(Notice(
                symbol: "arrow.down.circle.fill", tint: .blue, title: "Firmware update ready",
                detail: "Unplug tinyTouch and plug it back in to install it."
            ))
        }
        if !status.sensorReady {
            notices.append(Notice(
                symbol: "exclamationmark.triangle.fill", tint: .orange, title: "The sensor isn't responding",
                detail: "Unplug tinyTouch and plug it back in."
            ))
        }
        if store.fingers.enrolledCount == 0 {
            notices.append(Notice(
                symbol: "touchid", tint: .pink, title: "No fingerprints yet",
                detail: "Enroll a finger to sign in with a touch.",
                action: "Add Fingerprint"
            ) { store.settingsTab = .fingers })
        } else if let partial = store.fingers.fingers.first(where: { if case .partial = $0.state { true } else { false } }) {
            notices.append(Notice(
                symbol: "touchid", tint: .orange, title: "\(preferences.fingerName(partial.number)) is only partly enrolled",
                detail: "Scan it again so all four views are saved.",
                action: "Show"
            ) { store.settingsTab = .fingers })
        }
        switch status.mode {
        case .hid where status.hosts == 0 || !store.helperInstalled:
            notices.append(Notice(
                symbol: "key.fill", tint: .orange, title: "This Mac isn't set up for password entry",
                detail: "Run setup to save your password and register this Mac.",
                action: "Set Up…"
            ) { store.setupRequest = .hid })
        case .hid where !store.helperRunning:
            notices.append(Notice(
                symbol: "gearshape.2.fill", tint: .orange, title: "Password entry is stopped",
                detail: "The background helper isn't running.",
                action: "Repair"
            ) { Task { await store.repairHelper() } })
        case .piv where !status.pivReady:
            notices.append(Notice(
                symbol: "person.text.rectangle.fill", tint: .orange, title: "The smart card isn't set up",
                detail: "Run setup to create the identity and pair it with your account.",
                action: "Set Up…"
            ) { store.setupRequest = .piv })
        default:
            break
        }
        return notices
    }

    // MARK: - Recent activity

    private var recent: some View {
        let entries = Array(ActivityEntry.group(store.events).prefix(3))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                Spacer()
                Button("Show All") { store.settingsTab = .activity }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                if entries.isEmpty {
                    Text("No recent events.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    ForEach(entries) { entry in
                        if entry.id != entries.first?.id { Divider().padding(.leading, 46) }
                        ActivityRow(entry: entry, showsSteps: false)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
            }
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
        }
        .padding(.top, 4)
    }
}

extension DeviceMode {
    /// The mode without its protocol name, for places where space is short.
    var shortTitle: String {
        switch self {
        case .hid: "Password entry"
        case .piv: "Smart card"
        }
    }
}

/// A number or state on Overview that opens the tab it belongs to.
private struct StatTile: View {
    @Environment(DeviceStore.self) private var store
    let title: String
    let value: String
    var unit: String?
    var tint: Color?
    let tab: SettingsTab
    @State private var hovering = false

    var body: some View {
        Button {
            store.settingsTab = tab
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tint ?? .primary)
                        .contentTransition(.numericText())
                    if let unit {
                        Text(unit)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.quaternary.opacity(hovering ? 0.9 : 0.5), in: .rect(cornerRadius: 14))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(.snappy(duration: 0.2), value: hovering)
        .motion(.snappy, value: value)
        .help("Open \(tab.title)")
    }
}

private struct Notice: Identifiable {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    var action: String?
    var perform: () -> Void = {}

    var id: String { title }

    init(symbol: String, tint: Color, title: String, detail: String, action: String? = nil, perform: @escaping () -> Void = {}) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.detail = detail
        self.action = action
        self.perform = perform
    }
}

private struct NoticeBanner: View {
    @Environment(DeviceStore.self) private var store
    let notice: Notice

    var body: some View {
        HStack(spacing: 12) {
            OutcomeGlyph(symbol: notice.symbol, tint: notice.tint, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(notice.title)
                    .fontWeight(.semibold)
                Text(notice.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let action = notice.action {
                Button(action, action: notice.perform)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(notice.tint)
                    .disabled(store.isApproving)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(notice.tint.opacity(0.12), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(notice.tint.opacity(0.25))
        }
    }
}
