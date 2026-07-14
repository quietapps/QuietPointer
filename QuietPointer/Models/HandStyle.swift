import Foundation

/// Which glove artwork the pointer uses.
enum HandStyle: Int, CaseIterable {
    /// The upright pointing glove (index up, 10° tilt) with the leaning rod.
    case classic = 0
    /// The diagonal "mouse cursor" glove (index up-left, striped cuff) with a
    /// straight shadow beam that continues the arm's own axis.
    case comic = 1

    var title: String {
        switch self {
        case .classic: return "Classic glove"
        case .comic:   return "Comic glove"
        }
    }
}

/// Ink color for everything that isn't the glove: the trailing shadow rod and
/// the click bursts. The glove itself is always white.
enum PointerColor: Int, CaseIterable {
    /// The soft grey shadow and grey/blue bursts (the original look).
    case white = 0
    /// A dark shadow beam and black bursts — reads stronger on light desktops.
    case black = 1

    var title: String {
        switch self {
        case .white: return "White"
        case .black: return "Black"
        }
    }
}
