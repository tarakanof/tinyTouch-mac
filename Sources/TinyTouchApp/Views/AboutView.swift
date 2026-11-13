import SwiftUI

struct AboutView: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                    Text("tinyTouch")
                        .font(.title.weight(.semibold))
                    Text("Fingerprint sign-in for any Mac")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Versions") {
                LabeledContent("App", value: appVersion)
                LabeledContent("Command-line tool", value: store.cliVersion.isEmpty ? "—" : store.cliVersion)
                LabeledContent("Firmware") {
                    Text(store.status.map { "\($0.firmware) (\($0.build))" } ?? "Not connected")
                }
            }
            .textSelection(.enabled)

            Section("Authors") {
                LabeledContent("Hardware, firmware and CLI", value: "Zimeng Xiong")
                LabeledContent("macOS app", value: "Dmitrii Tarakanov")
            }

            Section("Links") {
                LinkRow(title: "Documentation", symbol: "book.fill",
                        url: "https://docs.tinytouch.dev/customer/setup")
                LinkRow(title: "CLI reference", symbol: "terminal.fill",
                        url: "https://docs.tinytouch.dev/reference/cli")
                LinkRow(title: "tinyTouch on GitHub", symbol: "chevron.left.forwardslash.chevron.right",
                        url: "https://github.com/ZimengXiong/tinyTouch")
                LinkRow(title: "This build's source", symbol: "arrow.triangle.branch",
                        url: "https://github.com/tarakanof/tinyTouch")
                LinkRow(title: "Sponsor the project", symbol: "heart.fill",
                        url: "https://github.com/sponsors/ZimengXiong")
            }

            Section {
                Text("MIT License. Copyright © 2026 Zimeng Xiong.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}

private struct LinkRow: View {
    let title: String
    let symbol: String
    let url: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack {
                SettingLabel(title: title, symbol: symbol)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
