import SwiftUI

struct LightingSettingsView: View {
    @Environment(DeviceStore.self) private var store
    @State private var draft = SettingsDraft(keys: [
        "led", "led_idle_color", "led_idle_end_color", "led_idle_effect", "led_idle_cycles",
        "led_success_color", "led_failure_color", "led_feedback_ms",
    ])
    @State private var previewDuration = 1500

    var body: some View {
        VStack(spacing: 0) {
            Form {
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
                            symbol: "lightbulb.fill",
                            color: .yellow,
                            info: "Fingerprint matching works in every lighting mode. Off also disables match and no-match feedback."
                        )
                    }
                }

                if store.status?.supportsCustomConfig == true {
                    idleSection
                    feedbackSection
                    presetSection
                } else {
                    Section {
                        Label("Update the firmware to customize colors and effects.", systemImage: "arrow.down.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            ApplyBar(changeCount: draft.changes.count, revert: draft.revert) {
                Task { _ = await store.apply(draft.changes) }
            }
        }
        .onAppear { draft.load(store.config) }
        .onChange(of: store.config) { draft.load(store.config) }
    }

    private var idleSection: some View {
        Section {
            LabeledContent {
                ColorSwatchPicker(selection: draft.string("led_idle_color"))
            } label: {
                SettingLabel(title: "Color", symbol: "paintpalette.fill", color: .blue)
            }
            LabeledContent {
                Picker("Effect", selection: draft.string("led_idle_effect")) {
                    ForEach(LEDEffect.allCases) { effect in
                        Text(effect.title).tag(effect.rawValue)
                    }
                }
                .labelsHidden()
                .fixedSize()
            } label: {
                SettingLabel(title: "Effect", symbol: "waveform.path", color: .purple)
            }
            if draft.values["led_idle_effect"] == LEDEffect.breathe.rawValue {
                LabeledContent {
                    ColorSwatchPicker(selection: draft.string("led_idle_end_color"))
                } label: {
                    SettingLabel(
                        title: "Breathe to",
                        symbol: "arrow.left.and.right",
                        color: .mint,
                        info: "Breathing fades between the idle color and this color."
                    )
                }
            }
            if draft.values["led_idle_effect"] != LEDEffect.steady.rawValue {
                NumberSettingRow(
                    title: "Repeats",
                    symbol: "repeat",
                    color: .gray,
                    info: "How many times the animation plays. 0 repeats it continuously.",
                    unit: "×",
                    value: draft.int("led_idle_cycles", in: 0...255),
                    range: 0...255
                )
            }
            LabeledContent {
                Button("Preview", systemImage: "play.fill") {
                    Task {
                        await store.preview(
                            color: LEDColor(rawValue: draft.values["led_idle_color"] ?? "") ?? .blue,
                            effect: LEDEffect(rawValue: draft.values["led_idle_effect"] ?? "") ?? .steady,
                            durationMs: previewDuration
                        )
                    }
                }
            } label: {
                SettingLabel(
                    title: "Try on device",
                    symbol: "eye.fill",
                    color: .teal,
                    info: "Shows the selected idle color and effect on the sensor for a moment without saving them."
                )
            }
        } header: {
            SectionHeader("Idle")
        }
    }

    private var feedbackSection: some View {
        Section {
            LabeledContent {
                ColorSwatchPicker(selection: draft.string("led_success_color"))
            } label: {
                SettingLabel(title: "Match", symbol: "checkmark", color: .green)
            }
            LabeledContent {
                ColorSwatchPicker(selection: draft.string("led_failure_color"))
            } label: {
                SettingLabel(title: "No match", symbol: "xmark", color: .red)
            }
            NumberSettingRow(
                title: "Duration",
                symbol: "timer",
                color: .orange,
                info: "How long the match or no-match color shows. Authentication continues meanwhile.",
                value: draft.int("led_feedback_ms", in: range("led_feedback_ms")),
                range: range("led_feedback_ms"),
                step: 50
            )
        } header: {
            SectionHeader("Authentication Feedback")
        }
    }

    private var presetSection: some View {
        Section {
            HStack(spacing: 10) {
                ForEach(LEDPreset.allCases) { preset in
                    Button {
                        Task { await store.applyPreset(preset) }
                    } label: {
                        VStack(spacing: 6) {
                            PresetSwatch(preset: preset)
                            Text(preset.title).font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .help("Apply the \(preset.title) theme")
                }
            }
            .padding(.vertical, 4)
        } header: {
            SectionHeader(
                "Themes",
                help: "A theme sets all colors and the idle effect at once, with a single touch. Lighting mode and feedback duration are kept."
            )
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
                    .padding(2)
                    .overlay {
                        if selection == color.rawValue {
                            Circle().strokeBorder(.tint, lineWidth: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(color.title)
                .accessibilityLabel(color.title)
                .accessibilityAddTraits(selection == color.rawValue ? .isSelected : [])
            }
        }
    }
}

private struct PresetSwatch: View {
    let preset: LEDPreset

    private var colors: [Color] {
        switch preset {
        case .default: [.blue, .green, .red]
        case .ocean: [.blue, .cyan, .red]
        case .neon: [.purple, .cyan, .green, .red]
        case .sunset: [.red, .yellow, .purple]
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(height: 36)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.1)))
    }
}
