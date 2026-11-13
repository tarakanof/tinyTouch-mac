import SwiftUI

/// System Settings–style icon: a white symbol on a colored rounded square.
/// Color belongs to the sidebar and page headers; form rows stay monochrome.
struct SettingIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .rect(cornerRadius: size * 0.27))
            .accessibilityHidden(true)
    }
}

struct SettingLabel: View {
    let title: String
    let symbol: String
    var info: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(title)
            if let info {
                InfoButton(text: info)
            }
        }
    }
}

/// Keeps explanations out of the way until the person asks for them.
struct InfoButton: View {
    let text: String
    var symbol = "info.circle"
    @State private var isShown = false

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("More information")
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading)
                .padding(14)
        }
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    var help: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if let help {
                InfoButton(text: help, symbol: "questionmark.circle")
            }
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, help: String? = nil) {
        self.init(title: title, help: help) { EmptyView() }
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .imageScale(.small)
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.15), in: .capsule)
        .contentTransition(.interpolate)
    }
}

struct ToggleRow: View {
    let title: String
    let symbol: String
    var info: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingLabel(title: title, symbol: symbol, info: info)
        }
        .toggleStyle(.switch)
    }
}

/// A symbol in a tinted circle, for list rows that report an outcome.
struct OutcomeGlyph: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16), in: .circle)
            .accessibilityHidden(true)
    }
}

// MARK: - Sensor

/// What the sensor ring is showing: a color, the effect that moves it, and the
/// color a breathing ring fades to.
struct SensorLight: Equatable {
    var color: Color?
    var endColor: Color?
    var effect = LEDEffect.steady

    /// A dark ring.
    static let off = SensorLight(color: nil)

    var animates: Bool { color != nil && effect != .steady }

    /// The ring's color and brightness at `time`, in seconds.
    func frame(at time: TimeInterval) -> (color: Color, brightness: Double)? {
        guard let color else { return nil }
        switch effect {
        case .steady:
            return (color, 1)
        case .breathe:
            let phase = (1 - cos(2 * .pi * time / 3.4)) / 2
            if let endColor, endColor != color {
                return (color.mix(with: endColor, by: phase), 1)
            }
            return (color, 0.25 + 0.75 * phase)
        case .flash:
            return (color, time.truncatingRemainder(dividingBy: 0.9) < 0.45 ? 1 : 0.12)
        case .fadeIn:
            return (color, time.truncatingRemainder(dividingBy: 2) / 2)
        case .fadeOut:
            return (color, 1 - time.truncatingRemainder(dividingBy: 2) / 2)
        }
    }
}

/// tinyTouch drawn on screen, with its sensor ring lit the way `light` describes.
struct SensorView: View {
    var light: SensorLight
    var size: CGFloat = 104
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !light.animates || reduceMotion)) { context in
            let time = reduceMotion ? 0.85 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(white: 0.24), Color(white: 0.07)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                            .strokeBorder(.white.opacity(0.14), lineWidth: max(0.5, size * 0.008))
                    }
                    .shadow(color: .black.opacity(0.3), radius: size * 0.1, y: size * 0.06)
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(white: 0.18), Color(white: 0.03)],
                        center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.4
                    ))
                    .frame(width: size * 0.62, height: size * 0.62)
                Image(systemName: "touchid")
                    .font(.system(size: size * 0.3, weight: .light))
                    .foregroundStyle(.white.opacity(0.3))
                if let frame = light.frame(at: time) {
                    Circle()
                        .strokeBorder(frame.color, lineWidth: max(1.5, size * 0.03))
                        .frame(width: size * 0.68, height: size * 0.68)
                        .shadow(color: frame.color, radius: size * 0.07)
                        .shadow(color: frame.color.opacity(0.7), radius: size * 0.16)
                        .opacity(frame.brightness)
                }
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

extension DeviceStore {
    /// The ring as the connected device shows it while idle.
    var idleLight: SensorLight {
        guard status != nil, config["led"] == LEDMode.on.rawValue else { return .off }
        return SensorLight(
            color: LEDColor(rawValue: config["led_idle_color"] ?? "")?.light,
            endColor: LEDColor(rawValue: config["led_idle_end_color"] ?? "")?.light,
            effect: LEDEffect(rawValue: config["led_idle_effect"] ?? "") ?? .steady
        )
    }
}

// MARK: - Motion

extension View {
    /// Animates changes of `value`, or applies them at once when Reduce Motion is on.
    func motion<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(Motion(animation: animation, value: value))
    }
}

private struct Motion<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
