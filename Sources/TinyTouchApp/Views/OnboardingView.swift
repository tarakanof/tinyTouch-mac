import SwiftUI

/// First-run setup, and later "Run Setup" from Maintenance. It drives `tinytouch setup`
/// in app mode and enrolls the first finger, so no step needs Terminal.
struct OnboardingView: View {
    @Environment(DeviceStore.self) private var store
    @Environment(AppPreferences.self) private var preferences

    let initialMode: DeviceMode?
    let isFirstRun: Bool

    @State private var step: Step = .welcome
    /// Which way the next page slides in.
    @State private var forward = true
    @State private var mode: DeviceMode = .hid
    @State private var password = ""
    /// The check of the password against the macOS account, while it runs.
    @State private var passwordCheck: Task<Void, Never>?
    @State private var confirmingMismatch = false

    enum Step: Int, CaseIterable {
        case welcome, connect, mode, credentials, working, enroll, done

        /// Position among the progress dots; entering credentials and the setup
        /// that follows are one stage.
        var stage: Int {
            switch self {
            case .welcome: 0
            case .connect: 1
            case .mode: 2
            case .credentials, .working: 3
            case .enroll: 4
            case .done: 5
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            StepDots(count: 6, current: step.stage)
                .padding(.top, 20)
            ScrollView {
                VStack(spacing: 24) {
                    hero
                    page
                        .id(step)
                        .transition(slide)
                }
                .frame(maxWidth: 440)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .background { Backdrop() }
        .onAppear(perform: start)
        .onDisappear(perform: stopPasswordCheck)
        .onChange(of: store.port) { if step == .connect, store.port != nil { go(to: .mode) } }
        .onChange(of: store.setupPhase) {
            guard step == .working else { return }
            if store.setupPhase == .done {
                go(to: store.fingers.enrolledCount == 0 ? .enroll : .done)
            } else if store.setupPhase == .idle {
                // Cancelled from the touch prompt.
                go(to: .credentials, forward: false)
            }
        }
        .sheet(item: Binding(
            get: { store.enrollment.map { EnrollmentID(finger: $0.finger) } },
            set: { if $0 == nil { store.cancelEnrollment() } }
        )) { _ in
            EnrollmentSheet()
        }
        .confirmationDialog("This isn't your Mac login password", isPresented: $confirmingMismatch) {
            Button("Use It Anyway") { runSetup() }
        } message: {
            Text("tinyTouch would type a password that doesn't unlock this Mac. Check it for typos, or continue if this is what you want typed.")
        }
        .motion(.smooth(duration: 0.4), value: step)
        .motion(.smooth(duration: 0.4), value: store.setupPhase)
    }

    private var slide: AnyTransition {
        .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    // MARK: - Pages

    /// The icon above each page. It stays in place and changes symbol and color,
    /// while the text below slides.
    @ViewBuilder
    private var hero: some View {
        if step == .welcome {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .transition(.blurReplace)
        } else {
            PageSymbol(symbol: heroSymbol.0, color: heroSymbol.1)
                .symbolEffect(.pulse, isActive: step == .working && store.setupPhase == .reconnect)
                .transition(.blurReplace)
        }
    }

    private var heroSymbol: (String, Color) {
        switch step {
        case .welcome, .connect: ("cable.connector", .blue)
        case .mode: ("lock.shield.fill", .blue)
        case .credentials: mode == .hid ? ("key.fill", .orange) : ("person.text.rectangle.fill", .indigo)
        case .working:
            switch store.setupPhase {
            case .reconnect: ("cable.connector.slash", .orange)
            case .failed: ("exclamationmark.triangle.fill", .red)
            default: ("gearshape.2.fill", .gray)
            }
        case .enroll: ("touchid", .pink)
        case .done: ("checkmark.circle.fill", .green)
        }
    }

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
            subtitle: "You can switch later in Sign-In."
        ) {
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
                PasswordField(title: "Password for \(NSFullUserName())", text: $password, onSubmit: next)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    // The password being checked is the one setup saves.
                    .disabled(checkingPassword)
            }
        } else {
            OnboardingPage(
                title: "Set up the smart card",
                subtitle: "tinyTouch creates a smart card identity and pairs it with your macOS account. macOS asks for your administrator password to pair it."
            ) {
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
                EmptyView()
            }
        case .failed(let message):
            OnboardingPage(title: "Setup didn't finish", subtitle: message) {
                EmptyView()
            }
        default:
            OnboardingPage(title: "Setting up tinyTouch", subtitle: workingText) {
                ProgressView().controlSize(.regular)
            }
        }
    }

    private var enroll: some View {
        OnboardingPage(
            title: "Add a fingerprint",
            subtitle: "tinyTouch scans your finger from four angles. You can add more fingers later."
        ) {
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
            Form {
                Toggle("Show in menu bar", isOn: $preferences.showInMenuBar)
                Toggle("Open at login", isOn: Binding(
                    get: { preferences.openAtLogin },
                    set: { try? preferences.setOpenAtLogin($0) }
                ))
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
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
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.enrollment != nil)
            } else if let title = primaryTitle {
                Button(title, action: next)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canContinue || checkingPassword)
            }
        }
        .buttonStyle(.glass)
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

    private func go(to next: Step, forward: Bool = true) {
        self.forward = forward
        step = next
    }

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
            go(to: store.port == nil ? .connect : .mode)
        case .connect:
            break
        case .mode:
            go(to: .credentials)
        case .credentials:
            guard canContinue, !checkingPassword else { return }
            guard mode == .hid else { return runSetup() }
            // A typo here would be typed at the lock screen, so check it against the account first.
            let password = password
            passwordCheck = Task {
                let matches = await AccountPassword.matches(password)
                // Back or Cancel left this page while the account was being checked.
                guard !Task.isCancelled else { return }
                passwordCheck = nil
                if matches == false { confirmingMismatch = true } else { runSetup() }
            }
        case .working:
            runSetup()
        case .enroll:
            go(to: .done)
        case .done:
            finish()
        }
    }

    private func runSetup() {
        go(to: .working)
        let secret = mode == .hid ? password : nil
        Task {
            if await store.runSetup(mode: mode, password: secret) { password = "" }
        }
    }

    private var checkingPassword: Bool { passwordCheck != nil }

    private func stopPasswordCheck() {
        passwordCheck?.cancel()
        passwordCheck = nil
    }

    private func back() {
        stopPasswordCheck()
        switch step {
        case .mode: go(to: .welcome, forward: false)
        case .credentials: go(to: .mode, forward: false)
        case .working:
            store.resetSetup()
            go(to: .credentials, forward: false)
        default: break
        }
    }

    private func finish() {
        stopPasswordCheck()
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

/// Where setup stands: a dot per stage, the current one drawn wide.
private struct StepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(.tint) : AnyShapeStyle(index < current ? .secondary : .quaternary))
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .motion(.bouncy(duration: 0.45), value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

/// A soft wash of color behind setup, strongest at the top.
private struct Backdrop: View {
    var body: some View {
        let base = Color(nsColor: .windowBackgroundColor)
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.45], [0.55, 0.35], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                .blue.mix(with: base, by: 0.7), .purple.mix(with: base, by: 0.74), .pink.mix(with: base, by: 0.78),
                .teal.mix(with: base, by: 0.88), base, .indigo.mix(with: base, by: 0.88),
                base, base, base,
            ]
        )
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct OnboardingPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.interpolate)
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
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 88, height: 88)
            .background(color.gradient, in: .rect(cornerRadius: 22))
            .shadow(color: color.opacity(0.35), radius: 14, y: 6)
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
        let selected = selection == mode
        Button {
            selection = mode
        } label: {
            HStack(alignment: .top, spacing: 12) {
                SettingIcon(symbol: symbol, color: mode == .hid ? .blue : .indigo, size: 28)
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
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(14)
            .contentShape(.rect(cornerRadius: 16))
            .glassEffect(selected ? .regular.tint(.accentColor.opacity(0.18)) : .regular, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .opacity(selected ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .motion(.snappy(duration: 0.25), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
