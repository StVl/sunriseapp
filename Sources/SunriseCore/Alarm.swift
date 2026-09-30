import Foundation

/// SPEC §12. One entry of the alarm list.
public struct Alarm: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var hour: Int
    public var minute: Int
    /// Mon…Sun.
    public var days: [Bool]
    public var sunriseMinutes: Int
    public var enabled: Bool
    public var spotify: SpotifyLink

    public init(
        id: UUID = UUID(),
        hour: Int = 7,
        minute: Int = 0,
        days: [Bool] = [true, true, true, true, true, false, false],
        sunriseMinutes: Int = 30,
        enabled: Bool = true,
        spotify: SpotifyLink = SpotifyLink()
    ) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.days = days
        self.sunriseMinutes = sunriseMinutes
        self.enabled = enabled
        self.spotify = spotify
    }

    private enum CodingKeys: String, CodingKey {
        case id, hour, minute, days, sunriseMinutes, enabled, spotify
    }

    /// Tolerant decoding: alarms saved before the list existed have no id.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Alarm()
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        hour = try c.decodeIfPresent(Int.self, forKey: .hour) ?? d.hour
        minute = try c.decodeIfPresent(Int.self, forKey: .minute) ?? d.minute
        days = try c.decodeIfPresent([Bool].self, forKey: .days) ?? d.days
        sunriseMinutes = Self.clampSunrise(try c.decodeIfPresent(Int.self, forKey: .sunriseMinutes) ?? d.sunriseMinutes)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        spotify = try c.decodeIfPresent(SpotifyLink.self, forKey: .spotify) ?? d.spotify
    }

    /// No days selected → rings once.
    public var isOnce: Bool { !days.contains(true) }

    public var daysLabel: String { DaysLabel.make(days) }

    public static let sunriseRange = 5...30
    /// The light starts this share of the sunrise *before* the alarm time.
    public static let leadFraction = 0.2

    static func clampSunrise(_ minutes: Int) -> Int {
        min(max(minutes, sunriseRange.lowerBound), sunriseRange.upperBound)
    }

    /// The alarm (wake-up) time: "07:00".
    public var timeText: String { TimeText.hhmm(hour, minute) }

    /// How long before the alarm time the light starts: 2/10 of the sunrise.
    public var leadSeconds: Double { Double(sunriseMinutes) * 60 * Self.leadFraction }

    /// Light starts at alarm − lead (07:00, 10 min → 06:58).
    public var lightStartText: String { clockText(offsetSeconds: -leadSeconds) }

    /// Full light at alarm − lead + sunrise (07:00, 10 min → 07:08).
    public var fullLightText: String { clockText(offsetSeconds: Double(sunriseMinutes) * 60 - leadSeconds) }

    /// Alarm time shifted by whole seconds, as "HH:mm" modulo 24h (seconds dropped).
    private func clockText(offsetSeconds: Double) -> String {
        let day = 24 * 3600
        let secs = ((hour * 3600 + minute * 60 + Int(offsetSeconds.rounded(.down))) % day + day) % day
        return TimeText.hhmm(secs / 3600, secs % 3600 / 60)
    }
}

/// What to play in the desktop Spotify app when the light starts.
public struct SpotifyLink: Codable, Equatable, Sendable {
    public var connected: Bool
    /// Display name of what plays, e.g. "Morning Light". Empty with no `uri`.
    public var playlist: String
    /// spotify:playlist:… / album / track …; nil = resume whatever played last.
    public var uri: String?

    public init(connected: Bool = false, playlist: String = "", uri: String? = nil) {
        self.connected = connected
        self.playlist = playlist
        self.uri = uri
    }
}

public enum SpotifyURI {
    static let kinds: Set<String> = ["playlist", "album", "track", "artist", "episode", "show"]

    /// Accepts an open.spotify.com link (as copied via Share → Copy link) or a spotify: URI.
    /// Returns the canonical "spotify:<kind>:<id>" or nil.
    public static func parse(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("spotify:") {
            let parts = text.split(separator: ":").map(String.init)
            guard parts.count == 3, kinds.contains(parts[1]), isID(parts[2]) else { return nil }
            return text
        }
        guard
            let url = URL(string: text),
            let host = url.host, host == "open.spotify.com" || host.hasSuffix(".spotify.com")
        else { return nil }
        // Path may carry a locale prefix: /intl-de/playlist/<id>.
        let parts = url.pathComponents.filter { $0 != "/" && !$0.hasPrefix("intl-") }
        guard parts.count >= 2, kinds.contains(parts[0]), isID(parts[1]) else { return nil }
        return "spotify:\(parts[0]):\(parts[1])"
    }

    /// Short share links from the phone app (spotify.link/…) have to be resolved over the network first.
    public static func isShortLink(_ input: String) -> Bool {
        guard let host = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines))?.host else { return false }
        return host == "spotify.link" || host.hasSuffix(".app.link")
    }

    /// First open.spotify.com/<kind>/<id> link anywhere in `text` (a redirect target or page body), as a URI.
    public static func find(in text: String) -> String? {
        let pattern = #"open\.spotify\.com/(?:intl-[a-zA-Z-]+/)?(playlist|album|track|artist|episode|show)/([A-Za-z0-9]+)"#
        guard
            let re = try? NSRegularExpression(pattern: pattern),
            let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let kind = Range(m.range(at: 1), in: text), let id = Range(m.range(at: 2), in: text)
        else { return nil }
        return "spotify:\(text[kind]):\(text[id])"
    }

    private static func isID(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isLetter || $0.isNumber }
    }
}

public enum TimeText {
    public static func hhmm(_ hour: Int, _ minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }
}

/// SPEC §6.3 caption under the day buttons.
public enum DaysLabel {
    static let short = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    public static func make(_ days: [Bool]) -> String {
        let selected = (0..<7).filter { days.indices.contains($0) && days[$0] }
        if selected.count == 7 { return "Every day" }
        if selected.isEmpty { return "Once" }
        if selected == [0, 1, 2, 3, 4] { return "Weekdays" }
        if selected == [5, 6] { return "Weekends" }

        var parts: [String] = []
        var i = 0
        while i < selected.count {
            var j = i
            while j + 1 < selected.count && selected[j + 1] == selected[j] + 1 { j += 1 }
            if j - i + 1 >= 3 {
                parts.append("\(short[selected[i]])–\(short[selected[j]])")
            } else {
                parts.append(contentsOf: selected[i...j].map { short[$0] })
            }
            i = j + 1
        }
        return parts.joined(separator: ", ")
    }
}
