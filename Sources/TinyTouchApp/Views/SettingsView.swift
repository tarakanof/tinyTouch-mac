import SwiftUI

struct SettingsView: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.settingsTab) {
            Tab("General", systemImage: "gearshape", value: SettingsTab.general) {
                DeviceGate { GeneralSettingsView() }
                    .frame(height: 735)
            }
            Tab("Lighting", systemImage: "lightbulb", value: SettingsTab.lighting) {
                DeviceGate { LightingSettingsView() }
                    .frame(height: 750)
            }
            Tab("Fingerprints", systemImage: "touchid", value: SettingsTab.fingers) {
                DeviceGate { FingersView() }
                    .frame(height: 560)
            }
            Tab("Computers", systemImage: "laptopcomputer", value: SettingsTab.computers) {
                DeviceGate { ComputersView() }
                    .frame(height: 360)
            }
            Tab("Maintenance", systemImage: "wrench.and.screwdriver", value: SettingsTab.maintenance) {
                MaintenanceView()
                    .frame(height: 640)
            }
        }
        .frame(width: 500)
        .sheet(item: Binding(
            get: { store.touchPrompt.map(IdentifiedPrompt.init) },
            set: { if $0 == nil { store.cancelApproval() } }
        )) { prompt in
            TouchPromptSheet(prompt: prompt.prompt)
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
