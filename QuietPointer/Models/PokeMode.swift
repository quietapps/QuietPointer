import Foundation
import CoreGraphics

/// The two looks for the rapid-click burst effect.
enum BurstDesign: Int, CaseIterable, Codable {
    case comic = 0    // cycling comic shapes (sparkle, spikes, ring, …)
    case ripple = 1   // single shockwave ring + rays in the glove tint

    var title: String {
        switch self {
        case .comic:  return "Comic pop"
        case .ripple: return "Ripple ring"
        }
    }
}

/// The four expressiveness modes for the click "poke" animation.
///
/// Each mode defines how far the hand jabs, how much it scales up, and how
/// fast the animation plays. `Speed-reactive intensity` (see `ClickMonitor`)
/// multiplies these base values when the user clicks in rapid succession.
enum PokeMode: Int, CaseIterable, Codable {
    case shy = 0        // Shy finger — a subtle nudge
    case gentle = 1
    case bold = 2
    case inYourFace = 3 // In your face — a wild jab

    var title: String {
        switch self {
        case .shy:        return "Shy finger"
        case .gentle:     return "Gentle nudge"
        case .bold:       return "Bold poke"
        case .inYourFace: return "In your face"
        }
    }

    /// How far (in points) the fingertip travels along the poke axis.
    var jabDistance: CGFloat {
        switch self {
        case .shy:        return 6
        case .gentle:     return 12
        case .bold:       return 20
        case .inYourFace: return 32
        }
    }

    /// Extra scale added at the peak of the poke (1.0 == no growth).
    var peakScale: CGFloat {
        switch self {
        case .shy:        return 1.06
        case .gentle:     return 1.14
        case .bold:       return 1.24
        case .inYourFace: return 1.40
        }
    }

    /// Total duration of one poke, in seconds. Faster modes feel snappier.
    var duration: CFTimeInterval {
        switch self {
        case .shy:        return 0.22
        case .gentle:     return 0.20
        case .bold:       return 0.18
        case .inYourFace: return 0.16
        }
    }

    /// A small rotational wobble (radians) at peak — bigger modes twist more.
    var wobble: CGFloat {
        switch self {
        case .shy:        return 0.02
        case .gentle:     return 0.05
        case .bold:       return 0.09
        case .inYourFace: return 0.16
        }
    }
}
