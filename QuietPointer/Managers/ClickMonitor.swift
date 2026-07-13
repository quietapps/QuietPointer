import Foundation
import CoreGraphics

/// Tracks click cadence. A single click stands alone; rapid clicks in
/// succession accumulate a count that drives bigger, cycling burst animations.
final class ClickMonitor {

    private var timestamps: [TimeInterval] = []
    /// Clicks within this window of each other count as one "multi-click" run.
    private let window: TimeInterval = 0.7

    /// Records a click now and returns how many clicks fall inside the current
    /// window (1 == an isolated single click).
    func registerClickAndCount() -> Int {
        let now = ProcessInfo.processInfo.systemUptime
        timestamps.append(now)
        timestamps.removeAll { now - $0 > window }
        return timestamps.count
    }

    func reset() {
        timestamps.removeAll()
    }
}
