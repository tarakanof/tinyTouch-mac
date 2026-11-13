import SwiftUI

struct FingersView: View {
    @Environment(DeviceStore.self) private var store
    @State private var pendingDelete: Finger?
    @State private var pendingReplace: Finger?

    var body: some View {
        Form {
            Section {
                ForEach(store.fingers.fingers) { finger in
                    FingerRow(
                        finger: finger,
                        enroll: { start(finger) },
                        delete: { pendingDelete = finger }
                    )
                }
            } header: {
                SectionHeader(
                    title: "Fingerprints",
                    help: "Each finger is scanned from four angles: left edge, right edge, top and center. Enrolling, replacing or deleting needs a touch from a finger that's already enrolled."
                ) {
                    Text("\(store.fingers.enrolledCount) of 10")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: Binding(
            get: { store.enrollment.map { EnrollmentID(finger: $0.finger) } },
            set: { if $0 == nil { store.cancelEnrollment() } }
        )) { _ in
            EnrollmentSheet()
        }
        .confirmationDialog(
            "Delete finger \(pendingDelete?.number ?? 0)?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { finger in
            Button("Delete", role: .destructive) {
                Task { await store.deleteFinger(finger.number) }
            }
        } message: { _ in
            Text(deleteMessage)
        }
        .confirmationDialog(
            "Replace finger \(pendingReplace?.number ?? 0)?",
            isPresented: Binding(get: { pendingReplace != nil }, set: { if !$0 { pendingReplace = nil } }),
            presenting: pendingReplace
        ) { finger in
            Button("Replace", role: .destructive) {
                store.enroll(finger: finger.number, replace: true)
            }
        } message: { _ in
            Text("All four existing views for this finger are removed before the new scan.")
        }
    }

    private var deleteMessage: String {
        if store.fingers.enrolledCount == 1 {
            return "This is the only enrolled finger. Without it, you can't approve changes until you enroll a new one."
        }
        return "All four views for this finger are removed from the sensor."
    }

    private func start(_ finger: Finger) {
        if finger.isOccupied {
            pendingReplace = finger
        } else {
            store.enroll(finger: finger.number, replace: false)
        }
    }
}

private struct EnrollmentID: Identifiable {
    let finger: Int
    var id: Int { finger }
}

private struct FingerRow: View {
    let finger: Finger
    let enroll: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            SettingIcon(
                symbol: finger.isOccupied ? "touchid" : "plus",
                color: finger.isOccupied ? badge.color : .gray.opacity(0.6)
            )
            Text("Finger \(finger.number)")
            StatusBadge(text: badge.text, color: badge.color, symbol: badge.symbol)
            Spacer()
            if finger.isOccupied {
                Button("Replace", systemImage: "arrow.triangle.2.circlepath", action: enroll)
                    .help("Scan this finger again")
                Button("Delete", systemImage: "trash", role: .destructive, action: delete)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.red)
                    .help("Delete finger \(finger.number)")
            } else {
                Button("Enroll", systemImage: "plus", action: enroll)
            }
        }
        .contextMenu {
            if finger.isOccupied {
                Button("Replace…", systemImage: "arrow.triangle.2.circlepath", action: enroll)
                Button("Delete…", systemImage: "trash", role: .destructive, action: delete)
            } else {
                Button("Enroll…", systemImage: "plus", action: enroll)
            }
        }
    }

    private var badge: (text: String, color: Color, symbol: String?) {
        switch finger.state {
        case .empty: ("Not enrolled", .secondary, nil)
        case .enrolled: ("Enrolled", .green, "checkmark")
        case .partial(let views): ("Partial · \(views)/4", .orange, "exclamationmark.triangle.fill")
        case .cleanupPending: ("Reconnect to clean up", .orange, "exclamationmark.triangle.fill")
        }
    }
}

struct EnrollmentSheet: View {
    @Environment(DeviceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let progress = store.enrollment ?? EnrollmentProgress(finger: 1)
        VStack(spacing: 18) {
            Text("Enroll Finger \(progress.finger)")
                .font(.title3.weight(.semibold))

            FingerprintViews(progress: progress)
                .frame(width: 150, height: 170)

            VStack(spacing: 4) {
                Text(title(progress.phase))
                    .font(.headline)
                Text(detail(progress.phase))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(minHeight: 48)

            ProgressView(value: Double(progress.completedScans), total: Double(EnrollmentProgress.totalScans))
                .frame(width: 220)

            HStack {
                switch progress.phase {
                case .done, .failed:
                    Button("Done") { store.enrollment = nil }
                        .keyboardShortcut(.defaultAction)
                default:
                    Button("Cancel", role: .cancel) { store.cancelEnrollment() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(28)
        .frame(width: 360)
        .interactiveDismissDisabled()
    }

    private func title(_ phase: EnrollmentProgress.Phase) -> String {
        switch phase {
        case .approving: "Approve with an enrolled finger"
        case .touch(let view, let second):
            "\(second ? "Again: " : "")Place the \(EnrollmentProgress.viewNames[safe: view - 1] ?? "finger")"
        case .lift: "Lift your finger"
        case .done: "Finger enrolled"
        case .failed: "Enrollment didn't finish"
        }
    }

    private func detail(_ phase: EnrollmentProgress.Phase) -> String {
        switch phase {
        case .approving:
            "Touch the sensor with a finger that's already enrolled. Skip this on a new device."
        case .touch(let view, _):
            "View \(view) of 4. Use the same new finger and hold it still."
        case .lift:
            "Lift your finger away from the sensor."
        case .done:
            "You can use this finger to authenticate now."
        case .failed(let message):
            "\(message) Other fingers were not changed."
        }
    }
}

private struct FingerprintViews: View {
    let progress: EnrollmentProgress

    var body: some View {
        ZStack {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .fontWeight(.ultraLight)
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: isWaitingForTouch)
            GeometryReader { proxy in
                ForEach(0..<4, id: \.self) { index in
                    ViewMarker(state: markerState(index))
                        .position(markerPosition(index, in: proxy.size))
                }
            }
        }
    }

    private var symbol: String {
        switch progress.phase {
        case .done: "checkmark.circle"
        case .failed: "xmark.circle"
        default: "touchid"
        }
    }

    private var tint: AnyShapeStyle {
        switch progress.phase {
        case .done: AnyShapeStyle(.green)
        case .failed: AnyShapeStyle(.red)
        default: AnyShapeStyle(.tint)
        }
    }

    private var isWaitingForTouch: Bool {
        if case .touch = progress.phase { return true }
        if case .approving = progress.phase { return true }
        return false
    }

    private var activeView: Int? {
        switch progress.phase {
        case .touch(let view, _), .lift(let view): view - 1
        default: nil
        }
    }

    private func markerState(_ index: Int) -> ViewMarker.State {
        let scans = min(max(progress.completedScans - index * 2, 0), 2)
        if scans == 2 { return .done }
        if activeView == index { return .active(scans) }
        return .pending
    }

    private func markerPosition(_ index: Int, in size: CGSize) -> CGPoint {
        switch index {
        case 0: CGPoint(x: 0, y: size.height * 0.55)
        case 1: CGPoint(x: size.width, y: size.height * 0.55)
        case 2: CGPoint(x: size.width / 2, y: 0)
        default: CGPoint(x: size.width / 2, y: size.height * 0.55)
        }
    }
}

private struct ViewMarker: View {
    enum State: Equatable {
        case pending, active(Int), done
    }

    let state: State

    var body: some View {
        ZStack {
            Circle()
                .fill(background)
                .frame(width: 26, height: 26)
            switch state {
            case .done:
                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
            case .active(let scans):
                HStack(spacing: 3) {
                    ForEach(0..<2, id: \.self) { scan in
                        Circle()
                            .fill(scan < scans ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.4)))
                            .frame(width: 5, height: 5)
                    }
                }
            case .pending:
                EmptyView()
            }
        }
        .animation(.snappy, value: state)
    }

    private var background: AnyShapeStyle {
        switch state {
        case .pending: AnyShapeStyle(.quaternary)
        case .active: AnyShapeStyle(.tint)
        case .done: AnyShapeStyle(.green)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
