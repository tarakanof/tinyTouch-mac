import SwiftUI

struct LightingSettingsView: View {
    @Environment(DeviceStore.self) private var store
    @State private var draft = SettingsDraft(keys: [
        "led", "led_idle_color", "led_idle_end_color", "led_idle_effect", "led_idle_cycles",
        "led_success_color", "led_failure_color", "led_feedback_ms",
    ])
    @State private var moment = Moment.idle

    /// Which of the ring's three states the on-screen preview shows.
    private enum Moment: String, CaseIterable, Identifiable {
        case idle, match, noMatch

        var id: String { rawValue }
        var title: String {
            switch self {
            case .idle: "Idle"
            case .match: "Match"
            case .noMatch: "No Match"
            }
        }
    }

    private var customizable: Bool { store.status?.supportsCustomConfig == true }

    var body: some View {
        Form {
            Section {
                stage
                    .listRowInsets(EdgeInsets())
            }
            Section {
                LabeledContent {
                    Picker("Sensor lighting", selection: draft.string("led")) {
                        ForEach(LEDMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    SettingLabel(
                        title: "Sensor lighting",
                        symbol: "lightbulb",
                        info: "Fingerprint matching works in every lighting mode. Off also disables match and no-match feedback."
                    )
                }
            }

            if customizable {
                idleSection
                feedbackSection
                themeSection
            } else {
                Section {
                    Label("Update the firmware to customize colors and effects.", systemImage: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .applyBar(draft) {
            Task { _ = await store.apply(draft.changes) }
        }
        .onAppear {
            draft.load(store.config)
            #if DEBUG
            if store.demoScene == "unsaved" { draft.values.merge(LEDPreset.ocean.settings) { _, new in new } }
            #endif
        }
        .onChange(of: store.config) { draft.load(store.config) }
        .motion(.smooth(duration: 0.3), value: draft.values["led_idle_effect"])
    }

    // MARK: - Preview

    /// The ring as the unsaved choices would light it.
    private var light: SensorLight {
        let mode = LEDMode(rawValue: draft.values["led"] ?? "") ?? .on
        func color(_ key: String) -> Color? { LEDColor(rawValue: draft.values[key] ?? "")?.light }
        switch moment {
        case .idle:
            guard mode == .on else { return .off }
            return SensorLight(
                color: color("led_idle_color"),
                endColor: color("led_idle_end_color"),
                effect: LEDEffect(rawValue: draft.values["led_idle_effect"] ?? "") ?? .steady
            )
        case .match:
            return mode == .off ? .off : SensorLight(color: color("led_success_color"), effect: .flash)
        case .noMatch:
            return mode == .off ? .off : SensorLight(color: color("led_failure_color"), effect: .flash)
        }
    }

    private var stage: some View {
        let light = light
        return VStack(spacing: 14) {
            SensorView(light: light, size: 124)
                .padding(.top, 6)
            Picker("Preview", selection: $moment) {
                ForEach(Moment.allCases) { moment in
                    Text(moment.title).tag(moment)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .environment(\.colorScheme, .dark)
            HStack(spacing: 6) {
                Text(light.color == nil ? "The ring is dark in this lighting mode." : "Preview. Nothing is saved until you apply.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                if customizable, moment == .idle, light.color != nil {
                    Button("Play on Device", systemImage: "play.fill") { play() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .tint(.white)
                        .disabled(store.isApproving)
                        .help("Shows this color and effect on the sensor for a moment. Asks for a touch and saves nothing.")
                }
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                LinearGradient(colors: [Color(white: 0.16), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)
                RadialGradient(
                    colors: [(light.color ?? .clear).opacity(0.32), .clear],
                    center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 220
                )
            }
        }
        .clipShape(.rect(cornerRadius: 12))
        .motion(.smooth(duration: 0.5), value: light)
    }

    private func play() {
        Task {
            await store.preview(
                color: LEDColor(rawValue: draft.values["led_idle_color"] ?? "") ?? .blue,
                effect: LEDEffect(rawValue: draft.values["led_idle_effect"] ?? "") ?? .steady,
                durationMs: 1500
            )
        }
    }

    /// Edits to a color or effect belong to the idle ring, so show it.
    private func idle(_ key: String) -> Binding<String> {
        let binding = draft.string(key)
        return Binding(get: { binding.wrappedValue }, set: {
            binding.wrappedValue = $0
            moment = .idle
        })
    }

    private func feedback(_ key: String, _ shown: Moment) -> Binding<String> {
        let binding = draft.string(key)
        return Binding(get: { binding.wrappedValue }, set: {
            binding.wrappedValue = $0
            moment = shown
        })
    }

    // MARK: - Sections

    private var idleSection: some View {
        Section {
            LabeledContent {
                ColorSwatchPicker(selection: idle("led_idle_color"))
            } label: {
                SettingLabel(title: "Color", symbol: "paintpalette")
            }
            LabeledContent {
                Picker("Effect", selection: idle("led_idle_effect")) {
                    ForEach(LEDEffect.allCases) { effect in
                        Text(effect.title).tag(effect.rawValue)
                    }
                }
                .labelsHidden()
                .fixedSize()
            } label: {
                SettingLabel(title: "Effect", symbol: "waveform.path")
            }
            if draft.values["led_idle_effect"] == LEDEffect.breathe.rawValue {
                LabeledContent {
                    ColorSwatchPicker(selection: idle("led_idle_end_color"))
                } label: {
                    SettingLabel(
                        title: "Breathe to",
                        symbol: "arrow.left.and.right",
                        info: "Breathing fades between the idle color and this color."
                    )
                }
            }
            if draft.values["led_idle_effect"] != LEDEffect.steady.rawValue {
                NumberSettingRow(
                    title: "Repeats",
                    symbol: "repeat",
                    info: "How many times the animation plays. 0 repeats it continuously.",
                    unit: "×",
                    value: draft.int("led_idle_cycles", in: 0...255),
                    range: 0...255
                )
            }
        } header: {
            SectionHeader("Idle")
        }
    }

    private var feedbackSection: some View {
        Section {
            LabeledContent {
                ColorSwatchPicker(selection: feedback("led_success_color", .match))
            } label: {
                SettingLabel(title: "Match", symbol: "checkmark")
            }
            LabeledContent {
                ColorSwatchPicker(selection: feedback("led_failure_color", .noMatch))
            } label: {
                SettingLabel(title: "No match", symbol: "xmark")
            }
            NumberSettingRow(
                title: "Duration",
                symbol: "timer",
                info: "How long the match or no-match color shows. Authentication continues meanwhile.",
                value: draft.int("led_feedback_ms", in: range("led_feedback_ms")),
                range: range("led_feedback_ms"),
                step: 50
            )
        } header: {
            SectionHeader("Authentication Feedback")
        }
    }

    private var themeSection: some View {
        Section {
            HStack(spacing: 10) {
                ForEach(LEDPreset.allCases) { preset in
                    ThemeCard(preset: preset, isSelected: isCurrent(preset)) {
                        draft.values.merge(preset.settings) { _, new in new }
                        moment = .idle
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            SectionHeader(
                "Themes",
                help: "A theme sets all colors and the idle effect at once. It's saved with your other changes when you apply. Lighting mode and feedback duration are kept."
            )
        }
    }

    private func isCurrent(_ preset: LEDPreset) -> Bool {
        preset.settings.allSatisfy { key, value in
            // Repeats don't matter while the ring is steady.
            draft.values[key] == value || (key == "led_idle_cycles" && preset.settings["led_idle_effect"] == LEDEffect.steady.rawValue)
        }
    }

    private func range(_ key: String) -> ClosedRange<Int> {
        store.catalog[key]?.range ?? 50...2000
    }
}

struct ColorSwatchPicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(LEDColor.allCases) { color in
                Button {
                    selection = color.rawValue
                } label: {
                    ZStack {
                        Circle()
                            .fill(color.swatch.gradient)
                            .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                        if color == .off {
                            Image(systemName: "line.diagonal")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 18, height: 18)
                    .padding(3)
                    .overlay {
                        if selection == color.rawValue {
                            Circle().strokeBorder(.tint, lineWidth: 2)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                    .scaleEffect(selection == color.rawValue ? 1.1 : 1)
                }
                .buttonStyle(.plain)
                .help(color.title)
                .accessibilityLabel(color.title)
                .accessibilityAddTraits(selection == color.rawValue ? .isSelected : [])
            }
        }
        .motion(.bouncy(duration: 0.3), value: selection)
    }
}

/// A theme shown as the three rings it sets: idle, match and no match.
private struct ThemeCard: View {
    let preset: LEDPreset
    let isSelected: Bool
    let choose: () -> Void
    @State private var hovering = false

    private var colors: [Color] {
        ["led_idle_color", "led_success_color", "led_failure_color"].compactMap { key in
            LEDColor(rawValue: preset.settings[key] ?? "")?.swatch
        }
    }

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 7) {
                HStack(spacing: 5) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .strokeBorder(color, lineWidth: 3)
                            .frame(width: 18, height: 18)
                            .shadow(color: color.opacity(0.6), radius: 3)
                    }
                }
                Text(preset.title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.quaternary.opacity(hovering || isSelected ? 0.9 : 0.5), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.tint, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(.snappy(duration: 0.25), value: isSelected)
        .help("Use the \(preset.title) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
