import DianaCore
import SwiftUI

extension Color {
    init(oklch l: Double, _ c: Double = 0, _ h: Double = 0) {
        let angle = h * .pi / 180
        let a = c * cos(angle)
        let b = c * sin(angle)
        let ll = pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let mm = pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let ss = pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
        func srgb(_ v: Double) -> Double {
            min(1, max(0, v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055))
        }
        self.init(
            .sRGB, red: srgb(4.0767416621 * ll - 3.3077115913 * mm + 0.2309699292 * ss),
            green: srgb(-1.2684380046 * ll + 2.6097574011 * mm - 0.3413193965 * ss),
            blue: srgb(-0.0041960863 * ll - 0.7034186147 * mm + 1.7076147010 * ss), opacity: 1)
    }
}

struct DianaTheme: Sendable {
    var dark = false
    var selectedAccent: Accent = .blue
    var background: Color { Color(oklch: dark ? 0.205 : 1) }
    var sidebar: Color { Color(oklch: dark ? 0.175 : 0.973, dark ? 0 : 0.006, 252) }
    var surface: Color { Color(oklch: dark ? 0.25 : 0.977, dark ? 0 : 0.004, 252) }
    var stage: Color { Color(oklch: dark ? 0.27 : 0.95, 0.012, hue) }
    var ink: Color { Color(oklch: dark ? 0.95 : 0.25, 0.014, 252) }
    var muted: Color { Color(oklch: dark ? 0.72 : 0.47, 0.018, 252) }
    var line: Color { Color(oklch: dark ? 0.34 : 0.915, 0.009, 252) }
    var accent: Color { Color(oklch: dark ? 0.73 : 0.478, 0.136, hue) }
    var button: Color { Color(oklch: 0.478, 0.136, hue) }
    var paleAccent: Color { Color(oklch: dark ? 0.31 : 0.945, 0.035, hue) }
    var success: Color { Color(oklch: dark ? 0.73 : 0.48, 0.105, 161) }
    var hue: Double {
        switch selectedAccent {
        case .blue: 251.8
        case .teal: 175
        case .coral: 28
        case .violet: 305
        }
    }
    func category(_ kind: ReminderKind) -> Color {
        let hue: Double =
            switch kind {
            case .task: 252
            case .water: 220
            case .meeting: 305
            case .rest: 155
            }
        return Color(oklch: dark ? 0.73 : 0.48, 0.115, hue)
    }
}

private struct DianaThemeKey: EnvironmentKey { static let defaultValue = DianaTheme() }
extension EnvironmentValues {
    var dianaTheme: DianaTheme {
        get { self[DianaThemeKey.self] }
        set { self[DianaThemeKey.self] = newValue }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.dianaTheme) private var theme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).padding(.horizontal, 16).padding(
            .vertical, 11
        ).foregroundStyle(.white).background(
            theme.button.opacity(enabled ? configuration.isPressed ? 0.84 : 1 : 0.4),
            in: RoundedRectangle(cornerRadius: 10)
        ).contentShape(RoundedRectangle(cornerRadius: 10)).scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct QuietButtonStyle: ButtonStyle {
    @Environment(\.dianaTheme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(
            .vertical, 9
        ).foregroundStyle(theme.ink).background(
            configuration.isPressed ? theme.line : theme.background, in: RoundedRectangle(cornerRadius: 9)
        ).overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.line, lineWidth: 1))
    }
}

struct SectionTitle: View {
    var title: String
    var subtitle: String? = nil
    @Environment(\.dianaTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.ink)
            if let subtitle {
                Text(subtitle).font(.system(size: 12)).foregroundStyle(theme.muted).fixedSize(
                    horizontal: false, vertical: true)
            }
        }
    }
}

struct Surface<Content: View>: View {
    @Environment(\.dianaTheme) private var theme
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading).background(
            theme.surface, in: RoundedRectangle(cornerRadius: 14)
        ).overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.line.opacity(0.6), lineWidth: 1))
    }
}

struct BrandMark: View {
    @Environment(\.dianaTheme) private var theme
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3).fill(theme.button)
            Image(systemName: "sparkle").font(.system(size: size * 0.60, weight: .medium)).foregroundStyle(
                .white)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
