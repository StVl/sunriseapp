import Foundation

/// A license activated on this Mac through Polar.
public struct LicenseRecord: Codable, Equatable, Sendable {
    public var key: String
    public var activationID: String
    public var activatedAt: Date
    public var lastValidatedAt: Date?

    public init(key: String, activationID: String, activatedAt: Date, lastValidatedAt: Date? = nil) {
        self.key = key
        self.activationID = activationID
        self.activatedAt = activatedAt
        self.lastValidatedAt = lastValidatedAt
    }
}

public enum LicenseState: Equatable, Sendable {
    /// First launch: neither a trial nor a license yet — the welcome screen asks.
    case undecided
    case trial(daysLeft: Int, endsAt: Date)
    case expired(endedAt: Date)
    case licensed

    /// The app's screens are open (otherwise the welcome screen or the paywall covers them).
    public var canUseApp: Bool {
        switch self {
        case .trial, .licensed: return true
        case .undecided, .expired: return false
        }
    }
}

public enum LicensePolicy {
    public static let trialDays = 30
    /// After the trial ends, alarms keep ringing for a day: one already set for tonight still wakes you.
    public static let graceAfterExpiry: TimeInterval = 24 * 3600
    /// How often an activated license is re-checked online (failures to connect never revoke it).
    public static let revalidateEvery: TimeInterval = 7 * 24 * 3600

    public static func state(trialStart: Date?, license: LicenseRecord?, now: Date) -> LicenseState {
        if license != nil { return .licensed }
        guard let trialStart else { return .undecided }
        let endsAt = trialStart.addingTimeInterval(Double(trialDays) * 24 * 3600)
        guard now < endsAt else { return .expired(endedAt: endsAt) }
        // Clock set back before the trial started: count from the start, not beyond 30 days.
        let remaining = min(endsAt.timeIntervalSince(now), Double(trialDays) * 24 * 3600)
        return .trial(daysLeft: max(1, Int((remaining / (24 * 3600)).rounded(.up))), endsAt: endsAt)
    }

    public static func alarmsMayRing(_ state: LicenseState, now: Date) -> Bool {
        switch state {
        case .licensed, .trial: return true
        case .undecided: return false
        case .expired(let endedAt): return now < endedAt.addingTimeInterval(graceAfterExpiry)
        }
    }

    public static func needsRevalidation(_ record: LicenseRecord, now: Date) -> Bool {
        now.timeIntervalSince(record.lastValidatedAt ?? record.activatedAt) >= revalidateEvery
    }

    /// Keys come from copy-paste: drop whitespace and line breaks around and inside.
    public static func normalize(_ key: String) -> String {
        key.components(separatedBy: .whitespacesAndNewlines).joined()
    }
}
