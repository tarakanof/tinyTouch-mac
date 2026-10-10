import SwiftUI

@main
struct TinyTouchApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var store = DeviceStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(store)
        } label: {
            MenuBarIcon(store: store, delegate: delegate)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(store)
        }
        .windowResizability(.contentSize)
    }
}

/// Opening the app again from Finder or Spotlight shows Settings, since it has no Dock icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var showSettings: (@MainActor () -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated { showSettings?() }
        return false
    }
}

private struct MenuBarIcon: View {
    let store: DeviceStore
    let delegate: AppDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(systemName: symbol)
            .symbolEffect(.pulse, isActive: store.touchPrompt != nil || store.enrollment != nil)
            .accessibilityLabel("tinyTouch")
            .task {
                delegate.showSettings = {
                    openSettings()
                    NSApp.activate()
                }
                if CommandLine.arguments.contains("--settings") {
                    delegate.showSettings?()
                }
                store.start()
            }
    }

    private var symbol: String {
        switch store.connection {
        case .connected: "touchid"
        default: "touchid.slash"
        }
    }
}
