import SwiftUI

/// Changes the password tinyTouch types, for every finger or for one finger.
struct ChangePasswordSheet: View {
    @Environment(DeviceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var finger = 0
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                SettingIcon(symbol: "key.fill", color: .orange)
                    .scaleEffect(1.4)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Change Password").font(.headline)
                    Text("tinyTouch types this password when your fingerprint matches.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding([.horizontal, .top], 20)

            Form {
                SecureField("New password", text: $password)
                SecureField("Confirm", text: $confirmation)
                if store.fingers.enrolledCount > 1 {
                    Picker("Use for", selection: $finger) {
                        Text("All fingers").tag(0)
                        ForEach(store.fingers.fingers.filter(\.isOccupied)) { finger in
                            Text("Finger \(finger.number) only").tag(finger.number)
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
                    .disabled(problem != nil || password.isEmpty || saving)
            }
            .padding(20)
        }
        .frame(width: 420)
    }

    private var problem: String? {
        if password.contains(where: \.isNewline) { return "The password can't contain line breaks." }
        if password.utf8.count > 160 { return "Use a password of 160 bytes or fewer." }
        if !confirmation.isEmpty, password != confirmation { return "The passwords don't match." }
        return nil
    }

    private func save() {
        guard password == confirmation else { return }
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
            SecureField("Login Keychain password", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(allow)
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
