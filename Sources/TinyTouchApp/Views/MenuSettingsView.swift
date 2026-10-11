import SwiftUI

/// Chooses what the menu bar item shows.
struct MenuSettingsView: View {
    @Environment(AppPreferences.self) private var preferences

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
                ToggleRow(
                    title: "Cross out icon when disconnected",
                    symbol: "touchid",
                    color: .pink,
                    isOn: $preferences.showsDisconnectedIcon
                )
                .disabled(!preferences.showInMenuBar)
            } header: {
                SectionHeader("Menu Bar")
            }

            Group {
                Section {
                    ForEach(MenuItem.status) { item in
                        itemToggle(item)
                    }
                } header: {
                    SectionHeader("Status")
                }

                Section {
                    ForEach(MenuItem.shortcuts) { item in
                        itemToggle(item)
                    }
                } header: {
                    SectionHeader("Shortcuts", help: "Open tinyTouch, Settings and Quit are always in the menu.")
                }

                Section {
                    MenuBarView()
                        .allowsHitTesting(false)
                        .background(.background.secondary, in: .rect(cornerRadius: 14))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } header: {
                    SectionHeader("Preview")
                }
            }
            .disabled(!preferences.showInMenuBar)
        }
        .formStyle(.grouped)
    }

    private func itemToggle(_ item: MenuItem) -> some View {
        ToggleRow(
            title: item.title,
            symbol: item.symbol,
            color: .gray,
            isOn: Binding(get: { preferences.shows(item) }, set: { preferences.setShows(item, $0) })
        )
    }
}
