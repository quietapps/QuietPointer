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

/// The two motions a click can play.
enum ClickMotion: Int, CaseIterable, Codable {
    /// Jab forward along the finger with an anticipation pull-back and a
    /// damped bounce settle (the Pokey-style poke).
    case poke = 0
    /// The whole hand + shadow recoils down along the shadow's axis, then
    /// springs back to the clicked position.
    case press = 1

    var title: String {
        switch self {
        case .poke:  return "Poke"
        case .press: return "Press"
        }
    }
}

/// One step of a poke: where in the animation it lands, how far the hand has
/// travelled along the finger axis, and how much it has twisted.
struct PokeKeyframe {
    /// Position within the animation, 0...1.
    let time: Float
    /// Travel along the finger axis, in points on a 150 pt-tall hand.
    /// Negative pulls back (anticipation), positive thrusts at the target.
    let travel: CGFloat
    /// Twist at this moment, in degrees.
    let twist: CGFloat
}

/// The four expressiveness tiers for the click "poke" animation.
///
/// With `Speed-reactive intensity` on (see `HandCursorView.poke`), the tier
/// escalates with click cadence — clicks landing within `ClickMonitor`'s
/// window each bump the poke one tier wilder, capped at `.inYourFace`. The
/// user's chosen mode is the starting tier for an isolated click.
enum PokeMode: Int, CaseIterable, Codable {
    case shy = 0        // Shy finger — a lift-and-settle nudge, no thrust
    case gentle = 1
    case bold = 2
    case inYourFace = 3 // In your face — a deep stab

    var title: String {
        switch self {
        case .shy:        return "Shy finger"
        case .gentle:     return "Gentle nudge"
        case .bold:       return "Bold poke"
        case .inYourFace: return "In your face"
        }
    }

    /// Compact rendering for tight UI like slider end labels.
    var shortTitle: String {
        switch self {
        case .shy:        return "Shy"
        case .gentle:     return "Gentle"
        case .bold:       return "Bold"
        case .inYourFace: return "Wild"
        }
    }

    /// Total duration of one poke, in seconds. Wilder tiers run longer —
    /// the extra time goes into the bounce settle, not a slower stab.
    var pokeDuration: CFTimeInterval {
        switch self {
        case .shy:        return 0.36
        case .gentle:     return 0.44
        case .bold:       return 0.54
        case .inYourFace: return 0.70
        }
    }

    /// The poke motion: anticipation pull-back, thrust, damped settle.
    /// Travel values are tuned against a 150 pt hand and scale with the
    /// glove size at render time.
    var pokeKeyframes: [PokeKeyframe] {
        switch self {
        case .shy:
            return [PokeKeyframe(time: 0,    travel: 0,   twist: 0),
                    PokeKeyframe(time: 0.25, travel: -14, twist: 0),
                    PokeKeyframe(time: 0.55, travel: -5,  twist: 0),
                    PokeKeyframe(time: 0.75, travel: -9,  twist: 0),
                    PokeKeyframe(time: 1,    travel: 0,   twist: 0)]
        case .gentle:
            return [PokeKeyframe(time: 0,    travel: 0,   twist: 0),
                    PokeKeyframe(time: 0.15, travel: -12, twist: -2),
                    PokeKeyframe(time: 0.35, travel: 26,  twist: 3),
                    PokeKeyframe(time: 0.55, travel: 6,   twist: 1),
                    PokeKeyframe(time: 0.75, travel: 13,  twist: 2),
                    PokeKeyframe(time: 1,    travel: 0,   twist: 0)]
        case .bold:
            return [PokeKeyframe(time: 0,    travel: 0,   twist: 0),
                    PokeKeyframe(time: 0.10, travel: -12, twist: -2),
                    PokeKeyframe(time: 0.30, travel: 44,  twist: 4),
                    PokeKeyframe(time: 0.50, travel: 10,  twist: 1),
                    PokeKeyframe(time: 0.68, travel: 26,  twist: 3),
                    PokeKeyframe(time: 0.84, travel: 4,   twist: 0),
                    PokeKeyframe(time: 1,    travel: 0,   twist: 0)]
        case .inYourFace:
            return [PokeKeyframe(time: 0,    travel: 0,   twist: 0),
                    PokeKeyframe(time: 0.08, travel: -12, twist: -2),
                    PokeKeyframe(time: 0.26, travel: 92,  twist: 6),
                    PokeKeyframe(time: 0.31, travel: 18,  twist: 1),
                    PokeKeyframe(time: 0.42, travel: 26,  twist: 2),
                    PokeKeyframe(time: 0.57, travel: 0,   twist: 0),
                    PokeKeyframe(time: 1,    travel: 0,   twist: 0)]
        }
    }

    /// Base duration feeding the burst animations (the v1.1.2 poke duration —
    /// bursts were tuned against it and keep it). Faster modes feel snappier.
    var burstBaseDuration: CFTimeInterval {
        switch self {
        case .shy:        return 0.22
        case .gentle:     return 0.20
        case .bold:       return 0.18
        case .inYourFace: return 0.16
        }
    }

    /// How far (in points) the fingertip travels for the `press` motion.
    var jabDistance: CGFloat {
        switch self {
        case .shy:        return 6
        case .gentle:     return 12
        case .bold:       return 20
        case .inYourFace: return 32
        }
    }

    /// Total duration of one press, in seconds. Faster tiers feel snappier.
    var pressDuration: CFTimeInterval {
        switch self {
        case .shy:        return 0.53
        case .gentle:     return 0.48
        case .bold:       return 0.43
        case .inYourFace: return 0.38
        }
    }

    /// A small rotational wobble (radians) for the press recoil.
    var wobble: CGFloat {
        switch self {
        case .shy:        return 0.02
        case .gentle:     return 0.05
        case .bold:       return 0.09
        case .inYourFace: return 0.16
        }
    }

    /// The tier reached after `count` clicks in one rapid streak, starting
    /// from this tier: each extra click bumps one tier, capped at the top.
    func escalated(clicks count: Int) -> PokeMode {
        let raw = min(rawValue + max(0, count - 1), PokeMode.inYourFace.rawValue)
        return PokeMode(rawValue: raw) ?? .inYourFace
    }
}
