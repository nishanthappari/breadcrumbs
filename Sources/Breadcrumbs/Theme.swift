import AppKit
import SwiftUI

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    static func dynamic(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: dark, alpha: darkAlpha)
                : NSColor(hex: light, alpha: lightAlpha)
        }
    }
}

/// Semantic tokens from DESIGN.md.
enum Theme {
    static let paper = Color(nsColor: .dynamic(0xFBF9F4, 0x1D1C1A))
    static let card = Color(nsColor: .dynamic(0xFFFFFF, 0x262522))
    static let ink = Color(nsColor: .dynamic(0x2A2925, 0xEEEAE2))
    static let inkSoft = Color(nsColor: .dynamic(0x7A766D, 0xA29D93))
    static let rule = Color(nsColor: .dynamic(0xE4DFD4, 0x3A3833))
    static let tick = Color(nsColor: .dynamic(0x3E7A5A, 0x6DAF88))
    static let tickPressed = Color(nsColor: .dynamic(0x33684C, 0x7FBF98))
    static let tickInk = Color(nsColor: .dynamic(0xFBF9F4, 0x13261B))
    static let missed = Color(nsColor: .dynamic(0xE6E0D3, 0x4D4942))
    static let missedInk = Color(nsColor: .dynamic(0xA49D8E, 0x8E887C))
    static let live = Color(nsColor: .dynamic(0x3E7A5A, 0x6DAF88, lightAlpha: 0.14, darkAlpha: 0.22))
    static let wash = Color(nsColor: .dynamic(0xF3EFE6, 0x2C2B27))
    static let shadow = Color(nsColor: .dynamic(0x2A2925, 0x000000, lightAlpha: 0.12, darkAlpha: 0.45))

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func number(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.7)
}

enum Format {
    /// "4:32" — remaining seconds rounded up so the display never reads 0:00 early.
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "5 min" / "10 sec" / "1 hr".
    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) sec" }
        if s % 3600 == 0 { return "\(s / 3600) hr" }
        if s % 60 == 0 { return "\(s / 60) min" }
        return "\(s / 60)m \(s % 60)s"
    }

    static func boxes(_ n: Int) -> String { n == 1 ? "1 box" : "\(n) boxes" }
}
