import Foundation
import CoreGraphics

/// Tracks click cadence. A single click stands alone; rapid clicks in
/// succession accumulate a streak that drives wilder pokes and cycling bursts.
final class ClickMonitor {

    private var streak = 0
    private var lastClick: TimeInterval = -.infinity
    /// A gap longer than this since the previous click starts a new streak;
    /// any faster and the streak keeps growing, however long it runs.
    private let window: TimeInterval = 0.8

    /// Records a click now and returns the length of the current streak
    /// (1 == an isolated single click).
    func registerClickAndCount() -> Int {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastClick > window { streak = 0 }
        lastClick = now
        streak += 1
        return streak
    }

    func reset() {
        streak = 0
        lastClick = -.infinity
    }
}
