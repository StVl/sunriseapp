import CoreGraphics
import Foundation

/// Built-in display backlight via the private DisplayServices framework (as MonitorControl / Lunar do).
/// There is no public API for this; it rules out the Mac App Store but works on Apple Silicon laptops.
///
/// While armed the backlight goes down to `nightLevel`; during the sunrise it rises to 100%;
/// otherwise it's handed back to the user's own level. Changes are rate-limited, so every jump
/// (Set alarm, Stop, Snooze) becomes a short fade. The user's level is also kept in UserDefaults
/// so a crash can't leave the screen dark: the next launch puts it back.
@MainActor
final class Backlight {
    static let shared = Backlight()

    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let getFn: GetFn?
    private let setFn: SetFn?
    /// Full range per second: 50% → 100% takes half a second at most.
    private let maxSpeed: Float = 1.0
    /// Night floor. Not 0: at 0 a MacBook panel switches off entirely, which reads as "broken".
    static let nightLevel: Float = 1.0 / 16
    private static let savedKey = "backlightToRestore"

    /// The user's level before we took over; nil while we're not driving.
    private var saved: Float?
    private var level: Float = 0
    private var lastUpdate = Date()
    private var lastWrite = Date.distantPast

    private init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        getFn = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetFn.self) }
        setFn = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetFn.self) }
        // Left over from a crash while we were driving: give the user their brightness back.
        if let leftover = UserDefaults.standard.object(forKey: Self.savedKey) as? Float {
            write(leftover)
            UserDefaults.standard.removeObject(forKey: Self.savedKey)
        }
    }

    private var display: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(8, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    private func read() -> Float? {
        guard let getFn, let display else { return nil }
        var value: Float = 0
        return getFn(display, &value) == 0 ? value : nil
    }

    private func write(_ value: Float) {
        guard let setFn, let display else { return }
        _ = setFn(display, min(max(value, 0), 1))
    }

    /// Called ~30×/s. `target` maps the user's own level to the level wanted now;
    /// nil = not driving: fade back to the user's level and release.
    /// `insist`: rewrite the level every second even when it hasn't moved.
    func drive(_ target: ((Float) -> Float)?, insist: Bool = false, now: Date = Date()) {
        let dt = Float(min(now.timeIntervalSince(lastUpdate), 0.1))
        lastUpdate = now

        if target != nil, saved == nil {
            guard let current = read() else { return }
            saved = current
            level = current
            UserDefaults.standard.set(current, forKey: Self.savedKey)
        }
        guard let saved else { return }

        let goal = min(max(target?(saved) ?? saved, 0), 1)
        let step = maxSpeed * dt
        let next = level + min(max(goal - level, -step), step)
        // Otherwise written only when our target moves, so brightness keys pressed meanwhile aren't fought.
        if abs(next - level) > 0.0005 || (insist && now.timeIntervalSince(lastWrite) > 1) {
            level = next
            write(level)
            lastWrite = now
        }
        if target == nil, abs(level - saved) < 0.001 {
            release()
        }
    }

    /// Stop driving but leave the backlight where it is (after the alarm: stay bright).
    func keepCurrent() {
        saved = nil
        UserDefaults.standard.removeObject(forKey: Self.savedKey)
    }

    /// Immediate hand-back, e.g. on quit.
    func restore() {
        guard saved != nil else { return }
        release()
    }

    private func release() {
        guard let saved else { return }
        write(saved)
        self.saved = nil
        UserDefaults.standard.removeObject(forKey: Self.savedKey)
    }
}
