import Foundation

/// Keeps the screen on while an agent is watched (a chat or the live screen is open): the idle timer stays off for
/// `touchLimit` after the last touch, then iOS locks as usual. Pure decision; the app flips `isIdleTimerDisabled`.
public enum AwakePolicy {
    /// Seconds without a touch after which the screen may go dark again.
    public static let touchLimit: TimeInterval = 60

    public static func keepAwake(watching: Bool, lastTouch: Date, now: Date) -> Bool {
        watching && now.timeIntervalSince(lastTouch) < touchLimit
    }

    /// Seconds until the next decision (nil: nothing to wait for).
    public static func nextCheck(watching: Bool, lastTouch: Date, now: Date) -> TimeInterval? {
        guard keepAwake(watching: watching, lastTouch: lastTouch, now: now) else { return nil }
        return max(touchLimit - now.timeIntervalSince(lastTouch), 0.1)
    }
}
