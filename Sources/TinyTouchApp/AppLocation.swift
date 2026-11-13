import AppKit

/// Moves the app to Applications when it runs from a disk image or from a copy
/// macOS translocated. Setup records the CLI's path in the helper's launch agent,
/// so a path that goes away on eject or restart would break password entry.
@MainActor
enum AppLocation {
    static let destination = URL(fileURLWithPath: "/Applications/tinyTouch.app")

    static var needsMove: Bool {
        let bundle = Bundle.main.bundleURL
        if bundle.path.contains("/AppTranslocation/") { return true }
        let values = try? bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        return values?.volumeIsReadOnly == true
    }

    /// Asks to move the app, then opens the moved copy and quits this one.
    /// Returns only when no move is needed.
    static func moveIfNeeded() {
        guard needsMove else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Move tinyTouch to Applications?"
        alert.informativeText = """
            tinyTouch is running from the disk image. Its background helper needs \
            the app to stay in one place, so it has to be in the Applications folder.
            """
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Quit")
        guard alert.runModal() == .alertFirstButtonReturn else {
            NSApp.terminate(nil)
            return
        }
        do {
            try move()
        } catch {
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = "Couldn't move tinyTouch"
            failure.informativeText = """
                \(error.localizedDescription)

                Drag tinyTouch to the Applications folder in Finder, then open it from there.
                """
            failure.runModal()
            NSApp.terminate(nil)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    private static func move() throws {
        let fm = FileManager.default
        // An older copy may be running; it would keep the replaced files busy.
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        where app != .current {
            app.terminate()
        }
        if fm.fileExists(atPath: destination.path) {
            try fm.trashItem(at: destination, resultingItemURL: nil)
        }
        try fm.copyItem(at: Bundle.main.bundleURL, to: destination)
    }
}
