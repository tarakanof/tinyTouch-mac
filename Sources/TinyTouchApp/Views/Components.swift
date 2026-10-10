import SwiftUI

/// System Settings–style row icon: a white symbol on a colored rounded square.
struct SettingIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color.gradient, in: .rect(cornerRadius: 6))
            .accessibilityHidden(true)
    }
}

struct SettingLabel: View {
    let title: String
    let symbol: String
    let color: Color
    var info: String?

    var body: some View {
        HStack(spacing: 8) {
            SettingIcon(symbol: symbol, color: color)
            Text(title)
            if let info {
                InfoButton(text: info)
            }
        }
    }
}

/// Keeps explanations out of the way until the person asks for them.
struct InfoButton: View {
    let text: String
    var symbol = "info.circle"
    @State private var isShown = false

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("More information")
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading)
                .padding(14)
        }
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    var help: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if let help {
                InfoButton(text: help, symbol: "questionmark.circle")
            }
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, help: String? = nil) {
        self.init(title: title, help: help) { EmptyView() }
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .imageScale(.small)
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.15), in: .capsule)
    }
}

struct RefreshButton: View {
    @Environment(DeviceStore.self) private var store
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .disabled(store.isBusy)
        .help("Refresh")
    }
}

struct ToggleRow: View {
    let title: String
    let symbol: String
    let color: Color
    var info: String?
    @Binding var isOn: Bool

    var body: some View {
        LabeledContent {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        } label: {
            SettingLabel(title: title, symbol: symbol, color: color, info: info)
        }
    }
}
