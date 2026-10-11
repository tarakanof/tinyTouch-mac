import SwiftUI

/// How the app behaves on this Mac, as opposed to settings stored on the device.
struct AppSettingsView: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(DeviceStore.self) private var store
    @State private var error: String?

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section {
                ToggleRow(
                    title: "Show in menu bar",
                    symbol: "menubar.rectangle",
                    color: .blue,
                    info: "When off, tinyTouch opens as a regular window and quits when you close it. Password entry keeps working either way, because the background helper runs on its own.",
                    isOn: $preferences.showInMenuBar
                )
                LabeledContent {
                    HStack {
                        if preferences.loginItemStatus == .requiresApproval {
                            Button("Allow in System Settings…") { preferences.openLoginItemsSettings() }
                        }
                        Toggle("Open at login", isOn: Binding(
                            get: { preferences.openAtLogin },
                            set: { enabled in
                                do { try preferences.setOpenAtLogin(enabled) } catch { self.error = error.localizedDescription }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                } label: {
                    SettingLabel(title: "Open at login", symbol: "power", color: .green)
                }
                LabeledContent {
                    HStack {
                        if preferences.notificationsDenied {
                            Button("Open System Settings…") { preferences.openNotificationSettings() }
                        }
                        Toggle("Notifications", isOn: Binding(
                            get: { preferences.notificationsEnabled },
                            set: { enabled in Task { await preferences.setNotifications(enabled) } }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                } label: {
                    SettingLabel(
                        title: "Notifications",
                        symbol: "bell.badge.fill",
                        color: .red,
                        info: "Tells you when tinyTouch connects or disconnects, and when password entry stops working. Only while the app is running."
                    )
                }
            } header: {
                SectionHeader("Behavior")
            }

            Section {
                LabeledContent {
                    if preferences.commandLineToolInstalled {
                        StatusBadge(text: "Installed", color: .green)
                    } else {
                        Button(preferences.commandLineToolPath == nil ? "Install" : "Use This App's Version") {
                            do { try preferences.installCommandLineTool() } catch { self.error = error.localizedDescription }
                        }
                        .disabled(store.cli?.isBundled != true)
                    }
                } label: {
                    SettingLabel(
                        title: "tinytouch command",
                        symbol: "terminal.fill",
                        color: .gray,
                        info: "Adds the tinytouch command to ~/.local/bin so you can use it in Terminal. It runs the copy inside this app."
                    )
                }
            } header: {
                SectionHeader("Command Line")
            }
        }
        .formStyle(.grouped)
        .onAppear { preferences.refresh() }
        .alert("Couldn't change the setting", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }
}
