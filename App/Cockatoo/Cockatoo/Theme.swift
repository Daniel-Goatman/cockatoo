import SwiftUI
import AppKit
import LearnerCore

/// The sulphur-crested identity, translated from research/prototype-v2
/// (see docs/visual-redesign-plan.md). Graphite surfaces, ivory ink, one
/// gold crest. Words ripen cold → gold across the four user-facing stages;
/// terracotta is the functional miss colour; moss green stays reserved for
/// "connected". Gold means achievement — selection/focus is quietly indigo.
///
/// Every colour is a light/dark pair converted from the prototypes' oklch
/// tokens (oklch values in comments are the source of truth).
enum Theme {
    // MARK: - Surfaces

    /// Content background — oklch(21% 0 0) / oklch(96.5% 0.008 95)
    static let bg = dynamic(0x181818, 0xF5F3EE)
    /// Sidebar tint zone (no border; tint difference *is* the structure)
    static let sideBg = dynamic(0x101010, 0xEAE8E1)
    /// Card fill — slightly sunken from bg
    static let cardBg = dynamic(0x131313, 0xF8F7F2)
    /// Hover / raised fills
    static let surface = dynamic(0x222222, 0xE8E6DF)
    static let surface2 = dynamic(0x2B2B2B, 0xDFDCD4)

    // MARK: - Ink

    static let ink = dynamic(0xF2F2F2, 0x1F1C18)
    static let inkMuted = dynamic(0xABABAB, 0x5A554C)
    static let inkFaint = dynamic(0x8F8F8F, 0x736E65)

    // MARK: - Hairlines (cards/controls only — chrome zones have none)

    static let line = dynamic(0x353535, 0xDAD7D0)
    static let line2 = dynamic(0x484848, 0xC4C1B8)

    // MARK: - Selection / focus — indigo, never gold

    static let selection = dynamic(0x2F333B, 0xD7DEEC)
    static let selectionLine = dynamic(0x4A556C, 0xA2B1D2)

    // MARK: - The crest

    /// oklch(84% 0.16 90) / oklch(74% 0.155 85)
    static let gold = dynamic(0xF3C530, 0xD7A100)
    static let goldDeep = dynamic(0xD9AA1B, 0xAB7400)
    static let onGold = dynamic(0x261A0D, 0xFDFCF8)

    /// Reserved for connectivity + "unlocked" — never progress or rewards.
    static let live = dynamic(0x5BBE62, 0x33903C)

    // MARK: - Stage ramp (cold → gold; four user-facing stages)

    static let stageUpcoming = dynamic(0x7E8EA2, 0x586A83)
    static let stageOnPages = dynamic(0x89AEDD, 0x4369A2)
    static let stagePracticing = dynamic(0xE1B767, 0xA26F00)
    static let stageKnown = dynamic(0xF2C53A, 0xA77700)

    // MARK: - Answer outcomes (the ledger's five)

    static let outcomeIntroduced = dynamic(0x90B2EB, 0x577AB5)
    static let outcomeStrengthened = gold
    static let outcomeRepaired = dynamic(0xE5AB66, 0xC18434)
    static let outcomeAlmost = dynamic(0xD9906F, 0xBC6F4C)
    static let outcomeMissed = dynamic(0xCE6C54, 0xB14A31)

    static func stageColor(_ stage: Stage) -> Color {
        switch stage {
        case .locked: return stageUpcoming
        case .ambient, .ready: return stageOnPages
        case .learning: return stagePracticing
        case .known, .mastered: return stageKnown
        }
    }

    // MARK: - Type

    /// Target-language voice: Iowan Old Style (ships with macOS).
    static func serif(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .custom("Iowan Old Style", size: size).weight(weight)
    }

    /// Small structural labels (section heads, counts).
    static func monoLabel(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }

    // MARK: - Metrics

    static let cardRadius: CGFloat = 10
    static let controlRadius: CGFloat = 6
    /// Height of the floating window-controls row the sidebar clears.
    static let chromeTop: CGFloat = 52

    // MARK: - Helpers

    private static func dynamic(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

// MARK: - Card chrome

/// The standard raised card: sunken fill, hairline, prototype radius.
struct ThemeCard: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line))
    }
}

extension View {
    func themeCard(padding: CGFloat = 16) -> some View {
        modifier(ThemeCard(padding: padding))
    }
}

// MARK: - Buttons

/// The prototype pill: quiet capsule; the prominent variant carries the
/// signature gold underline-shadow that compresses on press.
struct PillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(prominent ? Theme.ink : Theme.inkMuted)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background {
                ZStack {
                    if prominent {
                        Capsule().fill(Theme.gold)
                            .offset(y: configuration.isPressed ? 1 : 2.5)
                    }
                    Capsule().fill(Theme.cardBg)
                    Capsule().strokeBorder(Theme.line2)
                }
            }
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var pillProminent: PillButtonStyle { PillButtonStyle(prominent: true) }
}

// MARK: - The mark

/// The cockatoo mark from the prototypes (32×32 design space): ivory body,
/// gold crest + cheek. Scales from the 17px sidebar brand to empty states.
struct CockatooMark: View {
    var bodyColor: Color = Theme.ink
    var crestColor: Color = Theme.gold
    var eyeColor: Color = .clear

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 32
            ZStack {
                CockatooBodyShape().fill(bodyColor)
                CockatooCrestShape().fill(crestColor)
                Circle()
                    .fill(eyeColor)
                    .frame(width: 2.3 * s, height: 2.3 * s)
                    .position(x: 14.4 * s, y: 8 * s)
                Circle()
                    .fill(crestColor)
                    .frame(width: 2 * s, height: 2 * s)
                    .position(x: 17.1 * s, y: 9.2 * s)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct CockatooBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 32
        var p = Path()
        p.move(to: CGPoint(x: 5 * s, y: 24 * s))
        p.addQuadCurve(to: CGPoint(x: 10 * s, y: 10 * s), control: CGPoint(x: 6 * s, y: 15 * s))
        p.addQuadCurve(to: CGPoint(x: 12.4 * s, y: 4.2 * s), control: CGPoint(x: 11.2 * s, y: 6.8 * s))
        p.addLine(to: CGPoint(x: 13.4 * s, y: 2 * s))
        p.addLine(to: CGPoint(x: 14.2 * s, y: 3.4 * s))
        p.addLine(to: CGPoint(x: 15 * s, y: 2.2 * s))
        p.addLine(to: CGPoint(x: 15.6 * s, y: 4 * s))
        p.addQuadCurve(to: CGPoint(x: 17 * s, y: 6.4 * s), control: CGPoint(x: 16 * s, y: 5.2 * s))
        p.addQuadCurve(to: CGPoint(x: 21 * s, y: 8.4 * s), control: CGPoint(x: 19.6 * s, y: 6.8 * s))
        p.addQuadCurve(to: CGPoint(x: 18.6 * s, y: 10 * s), control: CGPoint(x: 20.6 * s, y: 10 * s))
        p.addQuadCurve(to: CGPoint(x: 16.6 * s, y: 10.8 * s), control: CGPoint(x: 17.6 * s, y: 10.4 * s))
        p.addQuadCurve(to: CGPoint(x: 12 * s, y: 19 * s), control: CGPoint(x: 14 * s, y: 15 * s))
        p.addQuadCurve(to: CGPoint(x: 9 * s, y: 23.6 * s), control: CGPoint(x: 10.6 * s, y: 22 * s))
        p.addQuadCurve(to: CGPoint(x: 5 * s, y: 24 * s), control: CGPoint(x: 7 * s, y: 24.6 * s))
        p.closeSubpath()
        return p
    }
}

struct CockatooCrestShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 32
        var p = Path()
        p.move(to: CGPoint(x: 12.4 * s, y: 4.2 * s))
        p.addLine(to: CGPoint(x: 13.4 * s, y: 2 * s))
        p.addLine(to: CGPoint(x: 14.2 * s, y: 3.4 * s))
        p.addLine(to: CGPoint(x: 15 * s, y: 2.2 * s))
        p.addLine(to: CGPoint(x: 15.6 * s, y: 4 * s))
        p.addQuadCurve(to: CGPoint(x: 12.4 * s, y: 4.2 * s), control: CGPoint(x: 14 * s, y: 3.5 * s))
        p.closeSubpath()
        return p
    }
}
