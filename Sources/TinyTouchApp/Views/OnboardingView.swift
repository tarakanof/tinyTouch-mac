import SwiftUI

/// First-run setup, and later "Run Setup" from Maintenance. It drives `tinytouch setup`
/// in app mode and enrolls the first finger, so no step needs Terminal.
struct OnboardingView: View {
    @Environment(DeviceStore.self) private var store
    @Environment(AppPreferences.self) private var preferences

    let initialMode: DeviceMode?
    let isFirstRun: Bool

    @State private var step: Step = .welcome
    @State private var mode: DeviceMode = .hid
    @State private var password = ""

    enum Step: Int, CaseIterable {
        case welcome, connect, mode, credentials, working, enroll, done
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                page
                    .frame(maxWidth: 440)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .onAppear(perform: start)
        .onChange(of: store.port) { if step == .connect, store.port != nil { step = .mode } }
        .onChange(of: store.setupPhase) {
            guard step == .working else { return }
            if store.setupPhase == .done {
                step = store.fingers.enrolledCount == 0 ? .enroll : .done
            } else if store.setupPhase == .idle {
                // Cancelled from the touch prompt.
                step = .credentials
            }
        }
        .sheet(item: Binding(
            get: { store.enrollment.map { EnrollmentID(finger: $0.finger) } },
            set: { if $0 == nil { store.cancelEnrollment() } }
        )) { _ in
            EnrollmentSheet()
        }
        .animation(.default, value: step)
    }

    // MARK: - Pages

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome: welcome
        case .connect: connect
        case .mode: modePicker
        case .credentials: credentials
        case .working: working
        case .enroll: enroll
        case .done: done
        }
    }

    private var welcome: some View {
        OnboardingPage(
            title: "Welcome to tinyTouch",
            subtitle: "Sign in to your Mac with a fingerprint, even when it's closed and connected to a display."
        ) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                Feature(symbol: "touchid", color: .pink, title: "Touch to sign in",
                        detail: "Unlock your Mac and approve password prompts with a fingerprint.")
                Feature(symbol: "lock.shield.fill", color: .blue, title: "Stays on your Mac",
                        detail: "Fingerprints never leave the sensor, and your password stays in your login Keychain.")
                Feature(symbol: "lightbulb.fill", color: .orange, title: "Made yours",
                        detail: "Choose lighting, fingers, and how tinyTouch behaves.")
            }
        }
    }

    private var connect: some View {
        OnboardingPage(
            title: "Connect tinyTouch",
            subtitle: "Plug tinyTouch into this Mac with a USB data cable."
        ) {
            PageSymbol(symbol: "cable.connector", color: .blue)
        } content: {
            if case .failed(let message) = store.connection {
                VStack(spacing: 10) {
                    Text(message).foregroundStyle(.secondary)
                    Button("Try Again") { Task { await store.refreshAll() } }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for tinyTouch…").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var modePicker: some View {
        OnboardingPage(
            title: "Choose how to sign in",
            subtitle: "You can switch later in General."
        ) {
            PageSymbol(symbol: "lock.shield.fill", color: .blue)
        } content: {
            VStack(spacing: 10) {
                ModeCard(mode: .hid, symbol: "keyboard.fill", recommended: true, selection: $mode)
                ModeCard(mode: .piv, symbol: "person.text.rectangle.fill", recommended: false, selection: $mode)
            }
        }
    }

    @ViewBuilder
    private var credentials: some View {
        if mode == .hid {
            OnboardingPage(
                title: "Enter your Mac password",
                subtitle: "tinyTouch types it for you when your fingerprint matches. It's saved in your login Keychain and sent to the device only encrypted."
            ) {
                PageSymbol(symbol: "key.fill", color: .orange)
            } content: {
                SecureField("Password for \(NSFullUserName())", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .onSubmit(next)
            }
        } else {
            OnboardingPage(
                title: "Set up the smart card",
                subtitle: "tinyTouch creates a smart card identity and pairs it with your macOS account. macOS asks for your administrator password to pair it."
            ) {
                PageSymbol(symbol: "person.text.rectangle.fill", color: .indigo)
            } content: {
                Label("Keep your finger off the sensor while the identity is created.", systemImage: "hand.raised.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var working: some View {
        switch store.setupPhase {
        case .reconnect:
            OnboardingPage(
                title: "Reconnect tinyTouch",
                subtitle: "Unplug tinyTouch, then plug it back in to switch to \(mode.title.lowercased())."
            ) {
                PageSymbol(symbol: "cable.connector.slash", color: .orange)
                    .symbolEffect(.pulse)
            } content: {
                EmptyView()
            }
        case .failed(let message):
            OnboardingPage(title: "Setup didn't finish", subtitle: message) {
                PageSymbol(symbol: "exclamationmark.triangle.fill", color: .red)
            } content: {
                EmptyView()
            }
        default:
            OnboardingPage(title: "Setting up tinyTouch", subtitle: workingText) {
                PageSymbol(symbol: "gearshape.2.fill", color: .gray)
            } content: {
                ProgressView().controlSize(.regular)
            }
        }
    }

    private var enroll: some View {
        OnboardingPage(
            title: "Add a fingerprint",
            subtitle: "tinyTouch scans your finger from four angles. You can add more fingers later."
        ) {
            PageSymbol(symbol: "touchid", color: .pink)
        } content: {
            if store.fingers.enrolledCount > 0 {
                Label("Finger enrolled", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private var done: some View {
        @Bindable var preferences = preferences
        return OnboardingPage(
            title: "tinyTouch is ready",
            subtitle: mode == .hid
                ? "Touch the sensor at the lock screen or any password prompt."
                : "Touch the sensor at the login window and when macOS asks for your smart card."
        ) {
            PageSymbol(symbol: "checkmark.circle.fill", color: .green)
        } content: {
            Form {
                Toggle("Show in menu bar", isOn: $preferences.showInMenuBar)
                Toggle("Open at login", isOn: Binding(
                    get: { preferences.openAtLogin },
                    set: { try? preferences.setOpenAtLogin($0) }
                ))
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 120)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if canGoBack {
                Button("Back") { back() }
            }
            if !isFirstRun, step != .done {
                Button("Cancel") { finish() }
            }
            Spacer()
            if step == .enroll, store.fingers.enrolledCount == 0 {
                Button("Scan Finger") { store.enroll(finger: 1, replace: false) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.enrollment != nil)
            } else if let title = primaryTitle {
                Button(title, action: next)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canContinue)
            }
        }
        .controlSize(.large)
    }

    private var primaryTitle: String? {
        switch step {
        case .welcome: "Continue"
        case .connect: nil
        case .mode: "Continue"
        case .credentials: "Set Up"
        case .working:
            if case .failed = store.setupPhase { "Try Again" } else { nil }
        case .enroll: "Continue"
        case .done: "Done"
        }
    }

    private var canContinue: Bool {
        switch step {
        case .credentials: mode == .piv || !password.isEmpty
        default: true
        }
    }

    private var canGoBack: Bool {
        switch step {
        case .mode: isFirstRun
        case .credentials: true
        case .working: if case .failed = store.setupPhase { true } else { false }
        default: false
        }
    }

    private var workingText: String {
        if case .running(let text) = store.setupPhase { return text }
        return "Preparing tinyTouch…"
    }

    // MARK: - Navigation

    private func start() {
        store.resetSetup()
        if let initialMode { mode = initialMode }
        if isFirstRun {
            step = .welcome
        } else {
            step = store.port == nil ? .connect : (initialMode == nil ? .mode : .credentials)
        }
    }

    private func next() {
        switch step {
        case .welcome:
            step = store.port == nil ? .connect : .mode
        case .connect:
            break
        case .mode:
            step = .credentials
        case .credentials, .working:
            guard canContinue else { return }
            step = .working
            let secret = mode == .hid ? password : nil
            Task {
                if await store.runSetup(mode: mode, password: secret) { password = "" }
            }
        case .enroll:
            step = .done
        case .done:
            finish()
        }
    }

    private func back() {
        switch step {
        case .mode: step = .welcome
        case .credentials: step = .mode
        case .working:
            store.resetSetup()
            step = .credentials
        default: break
        }
    }

    private func finish() {
        password = ""
        store.resetSetup()
        store.setupRequest = nil
        preferences.hasCompletedSetup = true
    }
}

private struct EnrollmentID: Identifiable {
    let finger: Int
    var id: Int { finger }
}

private struct OnboardingPage<Header: View, Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 24) {
            header
            VStack(spacing: 8) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            content
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PageSymbol: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 44, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: 88, height: 88)
            .background(color.gradient, in: .rect(cornerRadius: 22))
    }
}

private struct Feature: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ModeCard: View {
    let mode: DeviceMode
    let symbol: String
    let recommended: Bool
    @Binding var selection: DeviceMode

    var body: some View {
        Button {
            selection = mode
        } label: {
            HStack(alignment: .top, spacing: 12) {
                SettingIcon(symbol: symbol, color: mode == .hid ? .blue : .indigo)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(mode.title).font(.headline)
                        if recommended {
                            StatusBadge(text: "Recommended", color: .blue)
                        }
                    }
                    Text(mode.summary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selection == mode ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selection == mode ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .padding(14)
            .contentShape(.rect)
            .background(.quaternary.opacity(selection == mode ? 0.8 : 0.4), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selection == mode ? Color.accentColor : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }
}
