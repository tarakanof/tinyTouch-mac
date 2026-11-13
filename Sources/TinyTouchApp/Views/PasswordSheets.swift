import OpenDirectory
import SwiftUI

/// A password field with a button that shows what was typed.
struct PasswordField: View {
    let title: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if revealed {
                    TextField(title, text: $text)
                        .autocorrectionDisabled()
                } else {
                    SecureField(title, text: $text)
                }
            }
            .onSubmit(onSubmit)
            Button {
                revealed.toggle()
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help(revealed ? "Hide the password" : "Show the password")
            .accessibilityLabel(revealed ? "Hide password" : "Show password")
        }
    }
}

enum AccountPassword {
    /// Whether `password` signs in to the current macOS account: nil when the
    /// account can't be checked here, such as a network account that is offline.
    /// A wrong guess counts as a failed sign-in attempt, like one at the lock screen.
    nonisolated static func matches(_ password: String) async -> Bool? {
        await Task.detached {
            guard let session = ODSession.default(),
                  let node = try? ODNode(session: session, type: ODNodeType(kODNodeTypeLocalNodes)),
                  let record = try? node.record(
                    withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil
                  ) else { return nil }
            do {
                try record.verifyPassword(password)
                return true
            } catch {
                return false
            }
        }.value
    }
}

/// Changes the password tinyTouch types, for every finger or for one finger.
struct ChangePasswordSheet: View {
    @Environment(DeviceStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var finger: Int
    @State private var saving = false
    @State private var confirmingMismatch = false
    /// The check of the password against the macOS account, while it runs.
    @State private var check: Task<Void, Never>?

    /// `finger` 0 means every finger.
    init(finger: Int = 0) {
        _finger = State(initialValue: finger)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                SettingIcon(symbol: "key.fill", color: .orange, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Change Password").font(.headline)
                    Text("tinyTouch types this password when your fingerprint matches.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding([.horizontal, .top], 20)

            Form {
                LabeledContent("New password") {
                    PasswordField(title: "New password", text: $password)
                        .labelsHidden()
                }
                LabeledContent("Confirm") {
                    PasswordField(title: "Confirm", text: $confirmation, onSubmit: save)
                        .labelsHidden()
                }
                if store.fingers.enrolledCount > 1 {
                    Picker("Use for", selection: $finger) {
                        Text("All fingers").tag(0)
                        ForEach(store.fingers.fingers.filter(\.isOccupied)) { finger in
                            Text("\(preferences.fingerName(finger.number)) only").tag(finger.number)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            if let problem {
                Label(problem, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .padding(.horizontal, 20)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(20)
        }
        .frame(width: 440)
        .confirmationDialog("This isn't your Mac login password", isPresented: $confirmingMismatch) {
            Button("Save Anyway") { commit(password) }
        } message: {
            Text("tinyTouch would type a password that doesn't unlock this Mac. Save it only if you use tinyTouch for something else.")
        }
        // Closing the sheet during the check must not save the password afterwards.
        .onDisappear { check?.cancel() }
    }

    private var canSave: Bool {
        problem == nil && !password.isEmpty && password == confirmation && !saving
    }

    private var problem: String? {
        if password.contains(where: \.isNewline) { return "The password can't contain line breaks." }
        if password.utf8.count > 160 { return "Use a password of 160 bytes or fewer." }
        if !confirmation.isEmpty, password != confirmation { return "The passwords don't match." }
        return nil
    }

    private func save() {
        guard canSave else { return }
        let password = password
        saving = true
        check = Task {
            let matches = await AccountPassword.matches(password)
            guard !Task.isCancelled else { return }
            if matches == false {
                saving = false
                confirmingMismatch = true
            } else {
                commit(password)
            }
        }
    }

    private func commit(_ password: String) {
        saving = true
        Task {
            let saved = await store.changePassword(password, finger: finger == 0 ? nil : finger)
            saving = false
            if saved { dismiss() }
        }
    }
}

/// Asked for when Keychain must trust the CLI inside this app before it can read saved credentials.
struct KeychainPasswordSheet: View {
    @Environment(DeviceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.rectangle.stack.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            VStack(spacing: 4) {
                Text("Allow tinyTouch to use saved passwords").font(.headline)
                Text("Enter your login Keychain password, usually your Mac password, so the background helper can read the credentials it needs.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            PasswordField(title: "Login Keychain password", text: $password, onSubmit: allow)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Not Now", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Allow", action: allow)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || store.isBusy)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func allow() {
        let secret = password
        password = ""
        Task { await store.repairHelper(keychainPassword: secret) }
    }
}
