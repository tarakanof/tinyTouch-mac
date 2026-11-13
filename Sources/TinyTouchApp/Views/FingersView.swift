import SwiftUI

struct FingersView: View {
    @Environment(DeviceStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @State private var selection = 1
    @State private var pendingDelete: Finger?
    @State private var pendingReplace: Finger?
    @State private var renaming: Finger?
    @State private var newName = ""
    @State private var passwordFinger: Finger?

    private var selected: Finger {
        store.fingers.fingers[safe: selection - 1] ?? Finger(number: 1, state: .empty)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Text("\(store.fingers.enrolledCount) of 10 enrolled")
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    InfoButton(
                        text: "Each finger is scanned from four angles: left edge, right edge, top and center. Enrolling, replacing or deleting needs a touch from a finger that's already enrolled.\n\nNames are kept on this Mac.",
                        symbol: "questionmark.circle"
                    )
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    ForEach(store.fingers.fingers) { finger in
                        FingerTile(
                            finger: finger,
                            name: preferences.fingerName(finger.number),
                            isSelected: finger.number == selection
                        ) {
                            selection = finger.number
                        }
                        .contextMenu { actions(for: finger) }
                    }
                }
                FingerDetail(
                    finger: selected,
                    name: preferences.fingerName(selected.number),
                    isLastMatch: store.lastMatchedFinger == selected.number
                ) {
                    actions(for: selected)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            if let first = store.fingers.fingers.first(where: \.isOccupied) { selection = first.number }
        }
        .motion(.bouncy(duration: 0.35), value: selection)
        .motion(.smooth(duration: 0.3), value: store.fingers.fingers.map(\.state))
        .sheet(item: Binding(
            get: { store.enrollment.map { EnrollmentID(finger: $0.finger) } },
            set: { if $0 == nil { store.cancelEnrollment() } }
        )) { _ in
            EnrollmentSheet()
        }
        .sheet(item: $passwordFinger) { finger in
            ChangePasswordSheet(finger: finger.number)
        }
        .alert(
            "Rename \(renaming.map { preferences.fingerName($0.number) } ?? "")",
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
            presenting: renaming
        ) { finger in
            TextField("Name", text: $newName)
            Button("Save") { preferences.setFingerName(newName, for: finger.number) }
            Button("Cancel", role: .cancel) {}
        } message: { finger in
            Text("For example, Right Index. Leave it empty to go back to Finger \(finger.number).")
        }
        .confirmationDialog(
            "Delete \(pendingDelete.map { preferences.fingerName($0.number) } ?? "")?",
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
            "Scan \(pendingReplace.map { preferences.fingerName($0.number) } ?? "") again?",
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

    @ViewBuilder
    private func actions(for finger: Finger) -> some View {
        if finger.isOccupied {
            Button("Rename…", systemImage: "pencil") {
                newName = preferences.hasFingerName(finger.number) ? preferences.fingerName(finger.number) : ""
                renaming = finger
            }
            Button("Scan Again…", systemImage: "arrow.triangle.2.circlepath") { pendingReplace = finger }
                .disabled(store.isApproving)
            if store.status?.mode == .hid {
                Button("Password…", systemImage: "key") { passwordFinger = finger }
                    .help("Type a different password for this finger")
            }
            Button("Delete…", systemImage: "trash", role: .destructive) { pendingDelete = finger }
                .disabled(store.isApproving)
        } else {
            Button("Enroll…", systemImage: "plus") {
                store.enroll(finger: finger.number, replace: false)
            }
            .disabled(store.isApproving)
        }
    }

    private var deleteMessage: String {
        if store.fingers.enrolledCount == 1 {
            return "This is the only enrolled finger. Without it, you can't approve changes until you enroll a new one."
        }
        return "All four views for this finger are removed from the sensor."
    }
}

private struct EnrollmentID: Identifiable {
    let finger: Int
    var id: Int { finger }
}

extension Finger {
    var tint: Color {
        switch state {
        case .empty: .secondary
        case .enrolled: .green
        case .partial, .cleanupPending: .orange
        }
    }
}

/// One of the ten slots on the sensor.
private struct FingerTile: View {
    let finger: Finger
    let name: String
    let isSelected: Bool
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                Image(systemName: finger.isOccupied ? "touchid" : "plus")
                    .font(.system(size: finger.isOccupied ? 28 : 16, weight: .light))
                    .foregroundStyle(finger.isOccupied ? AnyShapeStyle(finger.tint) : AnyShapeStyle(.tertiary))
                    .frame(height: 32)
                    .contentTransition(.symbolEffect(.replace))
                Text(finger.isOccupied ? name : "\(finger.number)")
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(finger.isOccupied ? .primary : .tertiary)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 82)
            .background(background, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                        style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: finger.isOccupied || isSelected ? [] : [4, 3])
                    )
            }
            .contentShape(.rect(cornerRadius: 16))
            .scaleEffect(isSelected ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(finger.isOccupied ? name : "Empty slot \(finger.number)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: AnyShapeStyle {
        if finger.isOccupied {
            return AnyShapeStyle(finger.tint.opacity(isSelected ? 0.16 : (hovering ? 0.13 : 0.09)))
        }
        return AnyShapeStyle(.quaternary.opacity(hovering || isSelected ? 0.5 : 0))
    }
}

/// The selected slot: its name, its state, and what can be done with it.
private struct FingerDetail<Actions: View>: View {
    let finger: Finger
    let name: String
    let isLastMatch: Bool
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SettingIcon(
                    symbol: finger.isOccupied ? "touchid" : "plus",
                    color: finger.isOccupied ? finger.tint : .gray,
                    size: 36
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(finger.isOccupied ? name : "Slot \(finger.number)")
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isLastMatch {
                    StatusBadge(text: "Matched most recently", color: .green, symbol: "checkmark")
                        .help("The newest match in the device log, as of the last time Activity was read.")
                }
            }
            HStack(spacing: 8) {
                actions
            }
            .labelStyle(.titleOnly)
            .buttonBorderShape(.capsule)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 16))
        .id(finger.number)
        .transition(.blurReplace)
    }

    private var subtitle: String {
        switch finger.state {
        case .empty: "Empty. Enroll a finger here."
        case .enrolled: "Slot \(finger.number) · all four views saved"
        case .partial(let views): "Slot \(finger.number) · \(views) of 4 views saved. Scan it again to finish."
        case .cleanupPending: "Unplug tinyTouch and plug it back in to finish cleaning up this slot."
        }
    }
}

// MARK: - Enrollment

struct EnrollmentSheet: View {
    @Environment(DeviceStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @State private var name = ""

    var body: some View {
        let progress = store.enrollment ?? EnrollmentProgress(finger: 1)
        VStack(spacing: 16) {
            Text("Enroll \(preferences.fingerName(progress.finger))")
                .font(.title3.weight(.semibold))

            ScanProgress(progress: progress)
                .frame(width: 176, height: 176)

            VStack(spacing: 4) {
                Text(title(progress.phase))
                    .font(.headline)
                    .contentTransition(.interpolate)
                Text(detail(progress.phase))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 52, alignment: .top)

            if progress.phase == .done, !preferences.hasFingerName(progress.finger) {
                TextField("Name, such as Right Index", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { finish(progress.finger) }
                    .transition(.blurReplace)
            }

            switch progress.phase {
            case .done, .failed:
                Button("Done") { finish(progress.finger) }
                    .keyboardShortcut(.defaultAction)
            default:
                Button("Cancel", role: .cancel) { store.cancelEnrollment() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(width: 360)
        .interactiveDismissDisabled()
        .motion(.smooth(duration: 0.3), value: progress.phase)
    }

    private func finish(_ finger: Int) {
        if store.enrollment?.phase == .done, !name.isEmpty {
            preferences.setFingerName(name, for: finger)
        }
        store.enrollment = nil
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

/// A fingerprint that fills as scans land, inside a ring with one arc per view:
/// left edge, right edge, top and center (drawn at the bottom).
private struct ScanProgress: View {
    let progress: EnrollmentProgress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    /// Where each view's arc is centered, in degrees clockwise from three o'clock.
    private static let centers: [Double] = [180, 0, 270, 90]
    private static let stroke = StrokeStyle(lineWidth: 7, lineCap: .round)

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                let scans = min(max(progress.completedScans - index * 2, 0), 2)
                arc(index, filled: 1)
                    .stroke(index == activeView ? AnyShapeStyle(.tint.opacity(0.35)) : AnyShapeStyle(.quaternary), style: Self.stroke)
                    .opacity(index == activeView && pulsing && !reduceMotion ? 0.45 : 1)
                    .animation(
                        index == activeView && !reduceMotion
                            ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
                        value: pulsing
                    )
                arc(index, filled: Double(scans) / 2)
                    .stroke(scans == 2 ? AnyShapeStyle(.green) : AnyShapeStyle(.tint), style: Self.stroke)
                    .opacity(scans == 0 ? 0 : 1)
            }
            center
                .frame(width: 92, height: 92)
        }
        .onAppear { pulsing = true }
        .motion(.smooth(duration: 0.45), value: progress.completedScans)
        .accessibilityElement()
        .accessibilityLabel("Scan progress")
        .accessibilityValue("\(progress.completedScans) of \(EnrollmentProgress.totalScans)")
    }

    private func arc(_ index: Int, filled: Double) -> some Shape {
        Circle()
            .inset(by: 4)
            .trim(from: 0.018, to: 0.018 + 0.214 * filled)
            .rotation(.degrees(Self.centers[index] - 45))
    }

    @ViewBuilder
    private var center: some View {
        switch progress.phase {
        case .failed:
            Image(systemName: "xmark.circle")
                .resizable()
                .scaledToFit()
                .fontWeight(.ultraLight)
                .foregroundStyle(.red)
                .transition(.blurReplace)
        default:
            let done = progress.phase == .done
            let fraction = Double(progress.completedScans) / Double(EnrollmentProgress.totalScans)
            ZStack {
                print.foregroundStyle(.quaternary)
                print
                    .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: 92 * fraction)
                    }
                    .symbolEffect(.bounce, value: done)
            }
        }
    }

    private var print: some View {
        Image(systemName: "touchid")
            .resizable()
            .scaledToFit()
            .fontWeight(.ultraLight)
    }

    private var activeView: Int? {
        switch progress.phase {
        case .touch(let view, _), .lift(let view): view - 1
        default: nil
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
