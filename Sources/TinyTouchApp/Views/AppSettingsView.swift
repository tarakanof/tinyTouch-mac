import SwiftUI

/// How the app behaves on this Mac, as opposed to settings stored on the device.
struct AppSettingsView: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(DeviceStore.self) private var store
    @Environment(Updater.self) private var updater
    @State private var error: String?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        Form {
            Section {
                ToggleRow(
                    title: "Open at login",
                    symbol: "power",
                    isOn: Binding(
                        get: { preferences.openAtLogin },
                        set: { enabled in
                            do { try preferences.setOpenAtLogin(enabled) } catch { self.error = error.localizedDescription }
                        }
                    )
                )
                if preferences.loginItemStatus == .requiresApproval {
                    LabeledContent("Allow tinyTouch in Login Items, then come back.") {
                        Button("Open Login Items…") { preferences.openLoginItemsSettings() }
                    }
                    .foregroundStyle(.secondary)
                }
                ToggleRow(
                    title: "Notifications",
                    symbol: "bell.badge.fill",
                    info: "Tells you when tinyTouch connects or disconnects, and when password entry stops working. Only while the app is running.",
                    isOn: Binding(
                        get: { preferences.notificationsEnabled },
                        set: { enabled in Task { await preferences.setNotifications(enabled) } }
                    )
                )
                if preferences.notificationsDenied {
                    LabeledContent("Turn on Allow notifications for tinyTouch, then come back.") {
                        Button("Open Notification Settings…") { preferences.openNotificationSettings() }
                    }
                    .foregroundStyle(.secondary)
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
                        info: "Adds the tinytouch command to ~/.local/bin so you can use it in Terminal. It runs the copy inside this app."
                    )
                }
            } header: {
                SectionHeader("Command Line")
            }

            if updater.isAvailable {
                Section {
                    @Bindable var updater = updater
                    ToggleRow(
                        title: "Check for updates automatically",
                        symbol: "arrow.triangle.2.circlepath",
                        info: "Looks for a new version once a day and asks before installing it.",
                        isOn: $updater.automaticallyChecksForUpdates
                    )
                    ToggleRow(
                        title: "Download updates in the background",
                        symbol: "arrow.down.circle.fill",
                        info: "Downloads a new version as soon as it's found and installs it when tinyTouch quits.",
                        isOn: $updater.automaticallyDownloadsUpdates
                    )
                    .disabled(!updater.automaticallyChecksForUpdates)
                    LabeledContent {
                        Button("Check Now") { updater.checkForUpdates() }
                            .disabled(!updater.canCheckForUpdates)
                    } label: {
                        SettingLabel(title: "Version \(appVersion)", symbol: "app.badge.fill")
                    }
                } header: {
                    SectionHeader("Updates")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { preferences.refresh() }
        .task { await preferences.refreshNotificationStatus() }
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
