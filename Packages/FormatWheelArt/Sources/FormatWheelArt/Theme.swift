import CoreGraphics

/// Highlight colour, named after the crew whose HUD colour it borrows (upstream Theme.swift `Crew`).
/// Full art port (glyphs, weapons, drawing, SFX) lands in P4.
public enum Crew: String, CaseIterable, Sendable {
    case online, michael, franklin, trevor

    /// sRGB components, identical to upstream.
    public var rgb: (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch self {
        case .online: return (0.20, 0.50, 0.90)
        case .michael: return (0.40, 0.71, 0.83)
        case .franklin: return (0.42, 0.82, 0.45)
        case .trevor: return (1.00, 0.60, 0.28)
        }
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }
}
