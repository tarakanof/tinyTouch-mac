import AppKit

// sudo runs this as SUDO_ASKPASS when the CLI pairs the smart card identity.
// It prints the password on stdout and exits 1 when the person cancels.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let alert = NSAlert()
alert.messageText = "tinyTouch wants to pair your smart card"
alert.informativeText = "Enter the administrator password for \(NSUserName()) to allow this."
let appBundle = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
if appBundle.pathExtension == "app" {
    alert.icon = NSWorkspace.shared.icon(forFile: appBundle.path)
}
let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
field.placeholderString = "Password"
alert.accessoryView = field
alert.addButton(withTitle: "OK")
alert.addButton(withTitle: "Cancel")
alert.window.initialFirstResponder = field
app.activate()

guard alert.runModal() == .alertFirstButtonReturn else { exit(1) }
print(field.stringValue)
