import SwiftUI
import UIKit

/// Design „Minze & Honig" (Spec 7).
///
/// Regeln: Pastell nur als Fläche, nie als Textfarbe (im Dark dürfen die
/// 300er als Text auf `#1F2221` stehen) · im Dark keine hellen Karten und
/// keine Schatten, Absetzung über 1.5 pt Border · Radien 8/12/16/24/999 ·
/// 4er-Spacing-Raster · Nunito gebundelt · Zahlen `tabular-nums` ·
/// Mindest-Touch 44 pt.
struct TrinkPalette: Sendable {
    let isDark: Bool
    let background: Color
    let surface: Color
    let subtle: Color
    let border: Color
    let text: Color
    let textStrong: Color
    let textSecondary: Color
    let green300: Color
    let green600: Color
    let green900: Color
    let yellow300: Color
    let yellow900: Color
    let purple300: Color
    let red600: Color
    let successBg: Color
    let warningBg: Color
    let errorBg: Color
    let infoBg: Color

    /// Löschen/Fehler als Textfarbe: `red-600` liegt im Dark zu dicht am
    /// Hintergrund, daher dort aufgehellt.
    var danger: Color { isDark ? Color(hex: 0xE59A95) : red600 }

    /// Akzent für ml-Werte: im Dark die 300er, im Light die 600er.
    var accentText: Color { isDark ? green300 : green600 }

    var borderWidth: CGFloat { isDark ? 1.5 : 1 }

    static let light = TrinkPalette(
        isDark: false,
        background: Color(hex: 0xFFFFFF),
        surface: Color(hex: 0xFFFFFF),
        subtle: Color(hex: 0xF4F7F5),
        border: Color(hex: 0xDFE4E1),
        text: Color(hex: 0x2E332F),
        textStrong: Color(hex: 0x1F2221),
        textSecondary: Color(hex: 0x5A635D),
        green300: Color(hex: 0xA8D5BA),
        green600: Color(hex: 0x47825F),
        green900: Color(hex: 0x22392C),
        yellow300: Color(hex: 0xF7E8A4),
        yellow900: Color(hex: 0x473A17),
        purple300: Color(hex: 0xCDB4DB),
        red600: Color(hex: 0xB3453E),
        successBg: Color(hex: 0xE8F3EC),
        warningBg: Color(hex: 0xFCF6E0),
        errorBg: Color(hex: 0xF7E7E6),
        infoBg: Color(hex: 0xF1EAF6)
    )

    static let dark = TrinkPalette(
        isDark: true,
        background: Color(hex: 0x1F2221),
        surface: Color(hex: 0x292D2B),
        subtle: Color(hex: 0x2E332F),
        border: Color(hex: 0x3A403C),
        text: Color(hex: 0xECEFED),
        textStrong: Color(hex: 0xFFFFFF),
        textSecondary: Color(hex: 0xA9B0AB),
        green300: Color(hex: 0xA8D5BA),
        green600: Color(hex: 0x47825F),
        green900: Color(hex: 0x22392C),
        yellow300: Color(hex: 0xF7E8A4),
        yellow900: Color(hex: 0x473A17),
        purple300: Color(hex: 0xCDB4DB),
        red600: Color(hex: 0xB3453E),
        successBg: Color(hex: 0x263B2F),
        warningBg: Color(hex: 0x3B3524),
        errorBg: Color(hex: 0x3F2523),
        infoBg: Color(hex: 0x352B3C)
    )

    static func resolve(_ scheme: ColorScheme) -> TrinkPalette {
        scheme == .dark ? .dark : .light
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Radien (Spec 7).
enum TrinkRadii {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let pill: CGFloat = 999
}

/// 4er-Spacing-Raster.
enum TrinkSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    /// Mindest-Touchfläche (Spec 7).
    static let minTouch: CGFloat = 44
}

// MARK: - Schrift

/// Nunito als variable Schrift: die Achse `wght` liefert 400 und 800 aus
/// derselben Datei. Fehlt die Schrift, fällt alles auf die Systemschrift.
enum TrinkFont {
    private static let postScriptName = "Nunito-ExtraLight"
    private static let wghtAxis: Int = 0x7767_6874 // 'wght'

    static let isAvailable: Bool = UIFont(name: postScriptName, size: 12) != nil

    static func uiFont(size: CGFloat, weight: CGFloat, textStyle: UIFont.TextStyle) -> UIFont {
        let base: UIFont
        if isAvailable {
            let variation: [NSNumber: CGFloat] = [NSNumber(value: wghtAxis): weight]
            let descriptor = UIFontDescriptor(fontAttributes: [
                .name: postScriptName,
                UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variation,
            ])
            base = UIFont(descriptor: descriptor, size: size)
        } else {
            base = .systemFont(ofSize: size, weight: weight >= 700 ? .heavy : .regular)
        }
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
    }
}

/// Textstufen wie im Flutter-Theme.
enum TrinkTextStyle {
    case displaySmall, headlineMedium, headlineSmall, titleLarge, titleMedium
    case bodyLarge, bodyMedium, bodySmall, labelLarge, labelMedium, caption

    var size: CGFloat {
        switch self {
        case .displaySmall: return 36
        case .headlineMedium: return 28
        case .headlineSmall: return 22
        case .titleLarge: return 20
        case .titleMedium: return 17
        case .bodyLarge: return 16
        case .bodyMedium: return 15
        case .bodySmall: return 13
        case .labelLarge: return 15
        case .labelMedium: return 13
        case .caption: return 12
        }
    }

    var bold: Bool {
        switch self {
        case .displaySmall, .headlineMedium, .headlineSmall, .titleLarge, .titleMedium, .labelLarge, .labelMedium: return true
        case .bodyLarge, .bodyMedium, .bodySmall, .caption: return false
        }
    }

    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .displaySmall: return .largeTitle
        case .headlineMedium: return .title1
        case .headlineSmall: return .title2
        case .titleLarge: return .title3
        case .titleMedium: return .headline
        case .bodyLarge: return .body
        case .bodyMedium: return .callout
        case .bodySmall: return .footnote
        case .labelLarge: return .callout
        case .labelMedium: return .footnote
        case .caption: return .caption1
        }
    }

    var font: Font {
        Font(TrinkFont.uiFont(size: size, weight: bold ? 800 : 400, textStyle: uiTextStyle))
    }
}

extension View {
    /// Textstufe anwenden; `tabular` schaltet feste Ziffernbreiten ein, damit
    /// ml-Werte nicht springen.
    func trinkText(_ style: TrinkTextStyle, tabular: Bool = false) -> some View {
        let font = style.font
        return self.font(tabular ? font.monospacedDigit() : font)
    }
}

// MARK: - Button-Stile

struct TrinkFilledButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let c = TrinkPalette.resolve(scheme)
        configuration.label
            .trinkText(.labelLarge)
            .foregroundStyle(c.green900)
            .padding(.horizontal, TrinkSpacing.lg)
            .frame(minHeight: TrinkSpacing.minTouch)
            .background(c.green300.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45))
            .clipShape(RoundedRectangle(cornerRadius: TrinkRadii.sm, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: TrinkRadii.sm, style: .continuous))
    }
}

struct TrinkOutlinedButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let c = TrinkPalette.resolve(scheme)
        configuration.label
            .trinkText(.labelLarge)
            .foregroundStyle(c.isDark ? c.text : c.green600)
            .padding(.horizontal, TrinkSpacing.lg)
            .frame(minHeight: TrinkSpacing.minTouch)
            .background(configuration.isPressed ? c.subtle : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: TrinkRadii.sm, style: .continuous)
                    .stroke(c.border, lineWidth: c.borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: TrinkRadii.sm, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

struct TrinkTextButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    var color: Color?

    func makeBody(configuration: Configuration) -> some View {
        let c = TrinkPalette.resolve(scheme)
        configuration.label
            .trinkText(.labelLarge)
            .foregroundStyle(color ?? (c.isDark ? c.text : c.green600))
            .padding(.horizontal, TrinkSpacing.sm)
            .frame(minHeight: TrinkSpacing.minTouch)
            .opacity(configuration.isPressed ? 0.6 : (isEnabled ? 1 : 0.4))
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == TrinkFilledButtonStyle {
    static var trinkFilled: TrinkFilledButtonStyle { TrinkFilledButtonStyle() }
}

extension ButtonStyle where Self == TrinkOutlinedButtonStyle {
    static var trinkOutlined: TrinkOutlinedButtonStyle { TrinkOutlinedButtonStyle() }
}

extension ButtonStyle where Self == TrinkTextButtonStyle {
    static var trinkText: TrinkTextButtonStyle { TrinkTextButtonStyle() }
    static func trinkText(color: Color) -> TrinkTextButtonStyle { TrinkTextButtonStyle(color: color) }
}
