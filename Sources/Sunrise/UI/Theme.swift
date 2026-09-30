import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: opacity
        )
    }

    /// 0–255 channels, like CSS rgba().
    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.init(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }
}

/// SPEC §3–5.
enum Theme {
    static let textPrimary = Color(hex: 0xfff6ec)
    static let textSecondary = Color(r: 255, g: 240, b: 225, a: 0.76)
    static let textTertiary = Color(r: 255, g: 240, b: 225, a: 0.62)
    static let textDark = Color(hex: 0x2a1204)
    static let cream = Color(hex: 0xfff1dc)
    static let toggleOn = Color(hex: 0xffb45c)
    static let windowBackground = Color(hex: 0x1a0c05)
    static let warmGlow = Color(r: 255, g: 190, b: 110, a: 0.35)

    /// Glass surfaces: how much of the blur material and the warm-dark tint sit over the lamp.
    static let glassMaterialOpacity = 0.7
    static let glassTintOpacity = 0.2

    /// macOS sheet curve cubic-bezier(0.32, 0.72, 0, 1).
    static func sheet(_ duration: Double) -> Animation {
        .timingCurve(0.32, 0.72, 0, 1, duration: duration)
    }
}

enum AppFont {
    /// SF Soft Time if installed, otherwise the system rounded design (SPEC §3).
    private static let softTimeAvailable = NSFontManager.shared.availableFontFamilies.contains("SF Soft Time")

    static func make(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if softTimeAvailable {
            return .custom("SF Soft Time", size: size).weight(weight).monospacedDigit()
        }
        return .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

// MARK: - Glass surface (SPEC §4)

struct GlassSurface: ViewModifier {
    var radius: CGFloat
    var shadowBlur: CGFloat = 80
    var shadowY: CGFloat = 30

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                // Shadow only outside the panel: under a see-through surface it would darken the glass.
                shape
                    .fill(Color.black)
                    .shadow(color: Color(r: 40, g: 10, b: 0, a: 0.35), radius: shadowBlur / 2, y: shadowY)
                    .mask {
                        ZStack {
                            Rectangle().padding(-(shadowBlur + shadowY) * 1.5)
                            shape.blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }
            }
            .background {
                // Lighter than SPEC §4 (0.42 tint, opaque material) so more of the lamp's light comes through.
                ZStack {
                    shape.fill(.ultraThinMaterial).opacity(Theme.glassMaterialOpacity)
                    shape.fill(Color(r: 28, g: 12, b: 4, a: Theme.glassTintOpacity))
                }
            }
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .overlay(
                // Top inner highlight.
                shape.strokeBorder(
                    LinearGradient(
                        stops: [.init(color: .white.opacity(0.14), location: 0), .init(color: .clear, location: 0.06)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
    }
}

extension View {
    func glass(radius: CGFloat, shadowBlur: CGFloat = 80, shadowY: CGFloat = 30) -> some View {
        modifier(GlassSurface(radius: radius, shadowBlur: shadowBlur, shadowY: shadowY))
    }

    /// Small uppercase label: "ALARM", "GOOD MORNING".
    func sectionLabel() -> some View {
        self
            .font(AppFont.make(13, .semibold))
            .tracking(13 * 0.08)
            .textCase(.uppercase)
            .foregroundColor(Theme.textSecondary)
    }
}

// MARK: - Buttons (SPEC §5)

struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }

    var kind: Kind
    var height: CGFloat = 36
    var fontSize: CGFloat = 14
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        PillButtonBody(configuration: configuration, style: self)
    }
}

private struct PillButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let style: PillButtonStyle
    @State private var hover = false

    var body: some View {
        configuration.label
            .font(AppFont.make(style.fontSize, .semibold))
            .foregroundColor(style.kind == .primary ? Theme.textDark : Theme.textPrimary)
            .padding(.horizontal, 18)
            .frame(maxWidth: style.fullWidth ? .infinity : nil)
            .frame(height: style.height)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(style.kind == .secondary ? Color.white.opacity(0.14) : .clear, lineWidth: 1))
            .shadow(color: style.kind == .primary ? Theme.warmGlow : .clear, radius: 9, y: 4)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Capsule())
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.15), value: hover)
    }

    private var fill: Color {
        switch style.kind {
        case .primary: return hover ? .white : Theme.cream
        case .secondary: return .white.opacity(hover ? 0.18 : 0.10)
        }
    }
}

/// Transparent button with a hover fill (SPEC §5 ghost).
struct GhostButtonStyle: ButtonStyle {
    var shape: AnyShape = AnyShape(Capsule())
    var hoverOpacity: Double = 0.08

    func makeBody(configuration: Configuration) -> some View {
        GhostButtonBody(configuration: configuration, style: self)
    }
}

private struct GhostButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let style: GhostButtonStyle
    @State private var hover = false

    var body: some View {
        configuration.label
            .background(style.shape.fill(Color.white.opacity(hover ? style.hoverOpacity : 0)))
            .contentShape(style.shape)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.15), value: hover)
            .environment(\.ghostHover, hover)
    }
}

private struct GhostHoverKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Lets a ghost button's label react to hover (e.g. the × icon turning white).
    var ghostHover: Bool {
        get { self[GhostHoverKey.self] }
        set { self[GhostHoverKey.self] = newValue }
    }
}
