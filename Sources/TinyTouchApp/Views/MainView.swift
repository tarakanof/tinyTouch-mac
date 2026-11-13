import SwiftUI

/// The app's main window: first-run setup, then device settings in a sidebar layout.
struct MainView: View {
    @Environment(DeviceStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.openWindow) private var openWindow
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        @Bindable var store = store
        Group {
            if let mode = store.setupRequest {
                OnboardingView(initialMode: mode, isFirstRun: false)
            } else if !preferences.hasCompletedSetup {
                OnboardingView(initialMode: nil, isFirstRun: true)
            } else {
                NavigationSplitView {
                    List(selection: $store.settingsTab) {
                        Section("Device") {
                            ForEach(SettingsTab.device, id: \.self) { tab in
                                SidebarLabel(tab: tab)
                            }
                        }
                        Section("tinyTouch") {
                            ForEach(SettingsTab.application, id: \.self) { tab in
                                SidebarLabel(tab: tab)
                            }
                        }
                    }
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
                    .toolbar(removing: .sidebarToggle)
                } detail: {
                    detail(for: store.settingsTab)
                        .id(store.settingsTab)
                        .transition(.blurReplace)
                        .navigationTitle(store.settingsTab.title)
                        .toolbar(removing: .title)
                        .toolbar {
                            // A toolbar item on every section also keeps the title bar,
                            // and the window controls in it, at one height.
                            ToolbarItem(placement: .navigation) {
                                Text(store.settingsTab.title)
                                    .font(.title2.weight(.semibold))
                                    .padding(.leading, 8)
                            }
                            .sharedBackgroundVisibility(.hidden)
                            ToolbarSpacer(.flexible)
                            ToolbarItem(placement: .primaryAction) {
                                ConnectionPill()
                            }
                        }
                        .motion(.smooth(duration: 0.28), value: store.settingsTab)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 560)
        .onAppear {
            AppDelegate.shared?.openWindow = openWindow
            preferences.mainWindowOpen = true
        }
        .onDisappear { preferences.mainWindowOpen = false }
        .onChange(of: activeState) {
            // Picks up changes made outside the app, such as new touches in Activity.
            if activeState == .key, preferences.hasCompletedSetup, !store.isBusy {
                Task { await refresh(store.settingsTab) }
            }
        }
        .onChange(of: store.isConfigured) {
            // Someone who already set up tinyTouch with the CLI skips the welcome flow.
            if store.isConfigured, !preferences.hasCompletedSetup, store.setupPhase == .idle {
                preferences.hasCompletedSetup = true
            }
        }
        .sheet(isPresented: Binding(
            get: { store.needsKeychainPassword },
            set: { store.needsKeychainPassword = $0 }
        )) {
            KeychainPasswordSheet()
        }
        .alert("Couldn't complete the action", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
        .overlay(alignment: .bottom) { ToastView() }
        .overlay { TouchPromptOverlay() }
    }

    @ViewBuilder
    private func detail(for tab: SettingsTab) -> some View {
        switch tab {
        case .overview: OverviewView()
        case .signIn: DeviceGate { SignInSettingsView() }
        case .lighting: DeviceGate { LightingSettingsView() }
        case .fingers: DeviceGate { FingersView() }
        case .computers: DeviceGate { ComputersView() }
        case .activity: DeviceGate { ActivityView() }
        case .maintenance: MaintenanceView()
        case .app: AppSettingsView()
        case .menu: MenuSettingsView()
        case .about: AboutView()
        }
    }

    private func refresh(_ tab: SettingsTab) async {
        guard store.port != nil else {
            // Nothing is connected as far as the app knows, so look again.
            await store.refreshAll()
            return
        }
        switch tab {
        case .overview, .signIn, .lighting: await store.refreshStatus(quiet: true)
        case .fingers: await store.refreshFingers()
        case .computers: await store.refreshHosts()
        case .activity: await store.refreshLogs()
        case .maintenance: await store.refreshHelper()
        case .app, .menu, .about: break
        }
    }
}

private struct SidebarLabel: View {
    let tab: SettingsTab

    var body: some View {
        Label {
            Text(tab.title)
        } icon: {
            SettingIcon(symbol: tab.symbol, color: tab.color)
        }
        .padding(.vertical, 3)
        .tag(tab)
    }
}

extension SettingsTab {
    static let device: [SettingsTab] = [.overview, .fingers, .lighting, .signIn, .computers, .activity, .maintenance]
    static let application: [SettingsTab] = [.app, .menu, .about]

    var title: String {
        switch self {
        case .overview: "Overview"
        case .signIn: "Sign-In"
        case .lighting: "Lighting"
        case .fingers: "Fingerprints"
        case .computers: "Computers"
        case .activity: "Activity"
        case .maintenance: "Maintenance"
        case .app: "Application"
        case .menu: "Menu Bar"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .signIn: "lock.fill"
        case .lighting: "lightbulb.fill"
        case .fingers: "touchid"
        case .computers: "laptopcomputer"
        case .activity: "waveform.path.ecg"
        case .maintenance: "wrench.and.screwdriver.fill"
        case .app: "switch.2"
        case .menu: "menubar.rectangle"
        case .about: "info"
        }
    }

    var color: Color {
        switch self {
        case .overview: .blue
        case .fingers: .pink
        case .lighting: .orange
        case .signIn: .indigo
        case .computers: .teal
        case .activity: .green
        case .maintenance, .app, .menu, .about: .gray
        }
    }
}

/// Shows a placeholder for tabs that need a connected device.
struct DeviceGate<Content: View>: View {
    @Environment(DeviceStore.self) private var store
    @ViewBuilder let content: Content

    var body: some View {
        if store.status != nil {
            content
        } else {
            DisconnectedMessage()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The connection, visible from every tab.
private struct ConnectionPill: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        HStack(spacing: 7) {
            ConnectionBadge(showsPort: false, font: .callout.weight(.medium))
            if store.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .help(store.port.map { "Connected on \($0.replacingOccurrences(of: "/dev/cu.", with: ""))" } ?? "")
        .motion(.snappy, value: store.isBusy)
        .motion(.snappy, value: store.connection)
    }
}

// MARK: - Touch prompt

/// The prompt for a touch or a reconnect, floating over the window. It stays for
/// the whole command, so it can change in place and end on a confirmation.
private struct TouchPromptOverlay: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        ZStack {
            if store.touchPrompt != nil {
                // Keeps clicks away from the window underneath while the device waits.
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .contentShape(.rect)
                    .transition(.opacity)
                TouchPromptPanel()
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            }
        }
        .motion(.bouncy(duration: 0.4), value: store.touchPrompt != nil)
    }
}

private struct TouchPromptPanel: View {
    @Environment(DeviceStore.self) private var store
    /// Keeps the text on screen while the panel animates away.
    @State private var shown = TouchPrompt(title: "", detail: "")

    var body: some View {
        let prompt = store.touchPrompt ?? shown
        let approved = prompt.phase == .approved
        VStack(spacing: 14) {
            TouchPromptSymbol(prompt: prompt, size: 84)
            VStack(spacing: 4) {
                Text(approved ? "Approved" : prompt.title)
                    .font(.headline)
                    .contentTransition(.interpolate)
                Text(detail(prompt))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let step = prompt.step, !approved {
                    Text(step)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .multilineTextAlignment(.center)
            Button("Cancel", role: .cancel) {
                store.cancelApproval()
            }
            .buttonStyle(.glass)
            .keyboardShortcut(.cancelAction)
            .opacity(approved ? 0 : 1)
            .disabled(approved)
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .frame(width: 270)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onChange(of: store.touchPrompt, initial: true) {
            if let current = store.touchPrompt { shown = current }
        }
        .motion(.smooth(duration: 0.3), value: prompt.phase)
    }

    private func detail(_ prompt: TouchPrompt) -> String {
        switch prompt.phase {
        case .waiting: prompt.detail
        case .finishing: "Finishing…"
        case .approved: prompt.title
        }
    }
}

/// The touch prompt's symbol in a tinted disc: ripples while it waits for a
/// finger, then a check once the command went through.
struct TouchPromptSymbol: View {
    let prompt: TouchPrompt
    var size: CGFloat = 84
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rippling = false

    private var approved: Bool { prompt.phase == .approved }
    private var tint: Color { approved ? .green : .accentColor }

    var body: some View {
        ZStack {
            if prompt.phase == .waiting, !reduceMotion {
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .strokeBorder(tint, lineWidth: 1.5)
                        .scaleEffect(rippling ? 1.5 : 1)
                        .opacity(rippling ? 0 : 0.7)
                        .animation(
                            .easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(Double(index) * 1.2),
                            value: rippling
                        )
                }
            }
            Circle()
                .fill(tint.opacity(0.15))
            Image(systemName: approved ? "checkmark" : prompt.symbol)
                .font(.system(size: size * 0.46, weight: approved ? .medium : .light))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: approved)
        }
        .frame(width: size, height: size)
        .onAppear { rippling = true }
        .accessibilityHidden(true)
    }
}

/// The touch prompt as a row, for the menu bar panel.
struct TouchPromptCard: View {
    let prompt: TouchPrompt

    var body: some View {
        HStack(spacing: 10) {
            TouchPromptSymbol(prompt: prompt, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.phase == .approved ? "Approved" : prompt.title)
                    .font(.callout.weight(.semibold))
                Text(prompt.phase == .approved ? prompt.title : prompt.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.12), in: .rect(cornerRadius: 12))
    }
}

private struct ToastView: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        ZStack {
            if let message = store.lastMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .symbolRenderingMode(.multicolor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect()
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .blurReplace))
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(4))
                        store.lastMessage = nil
                    }
            }
        }
        .motion(.bouncy(duration: 0.45), value: store.lastMessage)
    }
}

// MARK: - Apply bar

extension View {
    /// Floats a glass bar over the bottom of a settings form while `draft` holds
    /// unsaved edits. Saving them asks for a touch.
    func applyBar(_ draft: SettingsDraft, apply: @escaping () -> Void) -> some View {
        modifier(ApplyBarModifier(draft: draft, apply: apply))
    }
}

private struct ApplyBarModifier: ViewModifier {
    let draft: SettingsDraft
    let apply: () -> Void

    func body(content: Content) -> some View {
        let changes = draft.changes
        content
            .safeAreaBar(edge: .bottom) {
                if !changes.isEmpty {
                    ApplyBar(
                        changeCount: changes.count,
                        touchCount: DeviceStore.writes(for: changes).count,
                        revert: draft.revert,
                        apply: apply
                    )
                    .transition(.move(edge: .bottom).combined(with: .blurReplace))
                }
            }
            .motion(.bouncy(duration: 0.45), value: changes.isEmpty)
    }
}

private struct ApplyBar: View {
    @Environment(DeviceStore.self) private var store
    let changeCount: Int
    let touchCount: Int
    let revert: () -> Void
    let apply: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "touchid")
                .font(.title3)
                .foregroundStyle(.tint)
            HStack(spacing: 4) {
                Text(changeCount == 1 ? "1 change" : "\(changeCount) changes")
                    .fontWeight(.medium)
                    .contentTransition(.numericText())
                Text(touchCount == 1 ? "· 1 touch" : "· \(touchCount) touches")
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .help("Saving asks you to touch tinyTouch with an enrolled finger.")
            Button("Revert", action: revert)
                .padding(.leading, 6)
            Button("Apply", action: apply)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(store.isApproving)
        }
        .buttonBorderShape(.capsule)
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 12)
        .motion(.snappy, value: changeCount)
        .motion(.snappy, value: touchCount)
    }
}
