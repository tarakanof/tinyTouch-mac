import SwiftUI

/// The app's main window: first-run setup, then device settings in a sidebar layout.
struct MainView: View {
    @Environment(DeviceStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.openWindow) private var openWindow

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
                        ForEach(SettingsTab.allCases, id: \.self) { tab in
                            Label(tab.title, systemImage: tab.symbol)
                                .tag(tab)
                        }
                    }
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
                } detail: {
                    detail(for: store.settingsTab)
                        .navigationTitle(store.settingsTab.title)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                RefreshButton { await store.refreshAll() }
                            }
                        }
                }
            }
        }
        .frame(minWidth: 680, minHeight: 560)
        .onAppear {
            AppDelegate.shared?.openWindow = openWindow
            preferences.mainWindowOpen = true
        }
        .onDisappear { preferences.mainWindowOpen = false }
        .onChange(of: store.isConfigured) {
            // Someone who already set up tinyTouch with the CLI skips the welcome flow.
            if store.isConfigured, !preferences.hasCompletedSetup, store.setupPhase == .idle {
                preferences.hasCompletedSetup = true
            }
        }
        .sheet(item: Binding(
            get: { store.touchPrompt.map(IdentifiedPrompt.init) },
            set: { if $0 == nil { store.cancelApproval() } }
        )) { prompt in
            TouchPromptSheet(prompt: prompt.prompt)
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
    }

    @ViewBuilder
    private func detail(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: DeviceGate { GeneralSettingsView() }
        case .lighting: DeviceGate { LightingSettingsView() }
        case .fingers: DeviceGate { FingersView() }
        case .computers: DeviceGate { ComputersView() }
        case .maintenance: MaintenanceView()
        }
    }
}

extension SettingsTab: CaseIterable {
    static var allCases: [SettingsTab] { [.general, .lighting, .fingers, .computers, .maintenance] }

    var title: String {
        switch self {
        case .general: "General"
        case .lighting: "Lighting"
        case .fingers: "Fingerprints"
        case .computers: "Computers"
        case .maintenance: "Maintenance"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .lighting: "lightbulb"
        case .fingers: "touchid"
        case .computers: "laptopcomputer"
        case .maintenance: "wrench.and.screwdriver"
        }
    }
}

private struct IdentifiedPrompt: Identifiable {
    let prompt: TouchPrompt
    var id: String { prompt.title + (prompt.step ?? "") }
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

struct TouchPromptSheet: View {
    @Environment(DeviceStore.self) private var store
    let prompt: TouchPrompt

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "touchid")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)
            VStack(spacing: 4) {
                Text(prompt.title)
                    .font(.headline)
                Text(prompt.detail)
                    .foregroundStyle(.secondary)
                if let step = prompt.step {
                    Text(step)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .multilineTextAlignment(.center)
            Button("Cancel", role: .cancel) {
                store.cancelApproval()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(28)
        .frame(width: 300)
    }
}

struct TouchPromptCard: View {
    let prompt: TouchPrompt

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "touchid")
                .font(.title)
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)
            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.title).font(.callout.weight(.semibold))
                Text(prompt.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.12), in: .rect(cornerRadius: 10))
    }
}

private struct ToastView: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        if let message = store.lastMessage {
            Label(message, systemImage: "checkmark.circle.fill")
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect()
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation { store.lastMessage = nil }
                }
        }
    }
}

/// Form footer for staged edits; every saved change needs a fingerprint.
struct ApplyBar: View {
    let changeCount: Int
    let revert: () -> Void
    let apply: () -> Void

    var body: some View {
        HStack {
            if changeCount > 0 {
                Label(
                    changeCount == 1 ? "1 unsaved change" : "\(changeCount) unsaved changes",
                    systemImage: "touchid"
                )
                .foregroundStyle(.secondary)
                .help("Each saved change asks you to touch tinyTouch.")
            }
            Spacer()
            Button("Revert", action: revert)
                .disabled(changeCount == 0)
            Button("Apply", action: apply)
                .keyboardShortcut(.defaultAction)
                .disabled(changeCount == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
