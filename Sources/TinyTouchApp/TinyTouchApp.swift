import SwiftUI

@main
struct TinyTouchApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Window("tinyTouch", id: AppDelegate.mainWindow) {
            MainView()
                .environment(delegate.store)
                .environment(delegate.preferences)
        }
        .defaultSize(width: 780, height: 680)
        .defaultLaunchBehavior(delegate.opensWindowAtLaunch ? .presented : .suppressed)
        // Restored "closed" state would override the launch behavior above.
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About tinyTouch") { delegate.showMainWindow(tab: .about) }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { delegate.showMainWindow(tab: .app) }
                    .keyboardShortcut(",")
            }
        }

        MenuBarExtra(isInserted: Binding(
            get: { delegate.preferences.showInMenuBar },
            set: { delegate.preferences.showInMenuBar = $0 }
        )) {
            MenuBarView()
                .environment(delegate.store)
                .environment(delegate.preferences)
        } label: {
            MenuBarIcon(store: delegate.store, preferences: delegate.preferences, delegate: delegate)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let mainWindow = "main"
    @MainActor private(set) static weak var shared: AppDelegate?

    @MainActor let preferences = AppPreferences()
    @MainActor let store = DeviceStore()
    /// Captured from a live view, since only views can open SwiftUI windows.
    @MainActor var openWindow: OpenWindowAction?

    @MainActor var opensWindowAtLaunch: Bool {
        !preferences.showInMenuBar || !preferences.hasCompletedSetup
            || CommandLine.arguments.contains("--settings")
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            Self.shared = self
            store.preferences = preferences
            preferences.applyActivationPolicy()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { store.start() }
    }

    /// Opening the app again from Finder or Spotlight shows the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated { showMainWindow() }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated { !preferences.showInMenuBar }
    }

    @MainActor func showMainWindow(tab: SettingsTab? = nil) {
        if let tab { store.settingsTab = tab }
        openWindow?(id: Self.mainWindow)
        NSApp.activate()
    }
}

private struct MenuBarIcon: View {
    let store: DeviceStore
    let preferences: AppPreferences
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: symbol)
            .symbolEffect(.pulse, isActive: store.touchPrompt != nil || store.enrollment != nil)
            .accessibilityLabel("tinyTouch")
            .task {
                delegate.openWindow = openWindow
                if delegate.opensWindowAtLaunch { delegate.showMainWindow() }
            }
    }

    private var symbol: String {
        switch store.connection {
        case .connected: "touchid"
        default: preferences.showsDisconnectedIcon ? "touchid.slash" : "touchid"
        }
    }
}
