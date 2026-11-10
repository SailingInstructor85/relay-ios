import Foundation

/// Keeps the screen on while an agent is watched (a chat or the live screen is open): the idle timer stays off for
/// `touchLimit` after the last touch, then iOS locks as usual. A running microphone recording also keeps it on, for at
/// most `recordingLimit` from its start; the Sprachmodus pins it on while open. The reasons add up: the screen stays on
/// while any of them holds. Pure decision; the app flips `isIdleTimerDisabled`.
public enum AwakePolicy {
    /// Seconds without a touch after which the screen may go dark again.
    public static let touchLimit: TimeInterval = 60
    /// Longest stretch a single recording keeps the screen on (10 minutes); afterwards iOS locks as usual.
    public static let recordingLimit: TimeInterval = 600

    public static func keepAwake(watching: Bool, lastTouch: Date, now: Date) -> Bool {
        keepAwake(watching: watching, lastTouch: lastTouch, recordingSince: nil, pinned: false, now: now)
    }

    /// Seconds until the next decision (nil: nothing to wait for).
    public static func nextCheck(watching: Bool, lastTouch: Date, now: Date) -> TimeInterval? {
        nextCheck(watching: watching, lastTouch: lastTouch, recordingSince: nil, pinned: false, now: now)
    }

    /// `recordingSince`: start of the running recording (nil: none). `pinned`: a view that wants the screen on as long
    /// as it is open (Sprachmodus).
    public static func keepAwake(watching: Bool, lastTouch: Date, recordingSince: Date?, pinned: Bool, now: Date) -> Bool {
        pinned || touchLeft(watching: watching, lastTouch: lastTouch, now: now) != nil
            || recordingLeft(recordingSince, now: now) != nil
    }

    /// Seconds until a reason runs out and the decision may change (nil: nothing to wait for; pinned alone never
    /// runs out, it ends with the view).
    public static func nextCheck(watching: Bool, lastTouch: Date, recordingSince: Date?, pinned: Bool, now: Date) -> TimeInterval? {
        let left = [touchLeft(watching: watching, lastTouch: lastTouch, now: now), recordingLeft(recordingSince, now: now)]
            .compactMap { $0 }
        guard let soonest = left.min() else { return nil }
        return max(soonest, 0.1)
    }

    private static func touchLeft(watching: Bool, lastTouch: Date, now: Date) -> TimeInterval? {
        guard watching else { return nil }
        let left = touchLimit - now.timeIntervalSince(lastTouch)
        return left > 0 ? left : nil
    }

    private static func recordingLeft(_ since: Date?, now: Date) -> TimeInterval? {
        guard let since else { return nil }
        let left = recordingLimit - now.timeIntervalSince(since)
        return left > 0 ? left : nil
    }
}
