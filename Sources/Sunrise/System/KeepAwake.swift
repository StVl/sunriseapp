import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac awake enough for the alarm to ring.
@MainActor
final class KeepAwake {
    enum Level {
        case none
        /// An alarm is on: the display may sleep, the Mac itself must not (or the timer never fires).
        case system
        /// Night mode / ringing: the display stays on too, so the lock screen never covers the lamp.
        case display
    }

    private var assertion: IOPMAssertionID = 0
    private var activity: NSObjectProtocol?
    private var level = Level.none

    func set(_ new: Level) {
        guard new != level else { return }
        release()
        level = new
        let type: String
        let options: ProcessInfo.ActivityOptions
        switch new {
        case .none:
            return
        case .system:
            type = kIOPMAssertionTypePreventUserIdleSystemSleep
            options = [.userInitiated, .idleSystemSleepDisabled]
        case .display:
            type = kIOPMAssertionTypePreventUserIdleDisplaySleep
            options = [.userInitiated, .idleDisplaySleepDisabled, .idleSystemSleepDisabled]
        }
        IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Sunrise alarm" as CFString, &assertion)
        // Also opts out of App Nap so the alarm timer isn't coalesced.
        activity = ProcessInfo.processInfo.beginActivity(options: options, reason: "Sunrise alarm")
    }

    private func release() {
        if assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    /// Wakes the display if it went dark anyway (e.g. the user put it to sleep by hand).
    static func wakeDisplay() {
        var id: IOPMAssertionID = 0
        guard IOPMAssertionDeclareUserActivity("Sunrise alarm" as CFString, kIOPMUserActiveLocal, &id) == kIOReturnSuccess else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { IOPMAssertionRelease(id) }
    }
}
