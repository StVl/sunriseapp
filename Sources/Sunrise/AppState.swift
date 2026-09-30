import Foundation
import SunriseCore
import SwiftUI

/// What's on screen. `.editing` is the glass panel: the alarm list, or the editor when `draft` is set.
enum Phase: String {
    case editing, armed, ringing
}

/// Opacity tween for the brightness layer between states (SPEC §10: 1.4 s, cubic-bezier(0.4,0,0.2,1)).
private struct Tween {
    static let curve = CubicBezier(0.4, 0, 0.2, 1)

    var from: Double
    var to: Double
    var start: Date
    var duration: Double

    static func fixed(_ v: Double) -> Tween { Tween(from: v, to: v, start: .distantPast, duration: 0) }

    func value(at date: Date) -> Double {
        let t = duration > 0 ? date.timeIntervalSince(start) / duration : 1
        if t <= 0 { return from }
        if t >= 1 { return to }
        return from + (to - from) * Tween.curve(t)
    }
}

struct UpcomingAlarm {
    let alarm: Alarm
    /// When the light starts (the app rings then).
    let date: Date
    var isSnooze = false

    /// The wake-up time this light leads to (for a snooze: when it rings again).
    var alarmDate: Date { isSnooze ? date : date.addingTimeInterval(alarm.leadSeconds) }
}

@MainActor
final class AppState: ObservableObject {
    static let previewSeconds = 8.0
    static let snoozeSeconds = 9.0 * 60
    static let demoRingSeconds = 10.0
    static let demoSnoozeSeconds = 5.0
    static let dimTransition = 1.4
    static let spotifyMaxVolume = 75.0
    static let sleepCountdownSeconds = 3.0
    static let nightNightSeconds = 1.2

    /// Alarms ring whenever they're enabled and the app runs — on any screen, not only in night mode.
    @Published private(set) var alarms: [Alarm] {
        didSet { alarmsChanged() }
    }
    /// The alarm open in the editor (a copy; saved back on Save). nil = the list is showing.
    @Published var draft: Alarm?
    @Published private(set) var draftIsNew = false
    /// Earliest upcoming ring (snooze included).
    @Published private(set) var upcoming: UpcomingAlarm?

    @Published private(set) var phase: Phase = .editing
    /// "Screen goes dark in 3…" → "Night-night" before night mode. The start stays set after the
    /// toast hides, so it keeps showing "Night-night" while it fades out.
    @Published private(set) var sleepStart: Date?
    @Published private(set) var sleepToastVisible = false
    private var sleepWork: DispatchWorkItem?
    @Published private(set) var previewStart: Date?
    @Published private(set) var ringStart: Date?
    /// The alarm ringing now (or last): the ringing card shows it.
    @Published private(set) var ringingAlarm = Alarm()

    @Published var spotifyLink = SpotifyLink() { didSet { save() } }
    @Published private(set) var spotifyBusy = false
    @Published private(set) var spotifyError: String?
    let spotify = Spotify()

    /// Trial / license. The welcome screen or the paywall covers the panel when it says so.
    let license = LicenseManager()
    /// "License…" opened by hand (menu, trial badge) while the app is usable.
    @Published var showLicensePanel = false

    @Published var palette: LavaPalette.Name = .ember { didSet { save() } }
    /// Debug: ring for 10 s instead of the full sunrise, snooze for 5 s.
    @Published var demoTimings = false { didSet { save() } }
    /// At the peak of the sunrise: backlight to 100% and the lamp past SDR white (EDR).
    @Published var hdrBoost = true { didSet { save() } }
    /// Night mode, in front: backlight down to `Backlight.nightLevel`, so the room stays dark.
    @Published var dimAtNight = true { didSet { save() } }

    let intensity = 1.1
    private(set) var ringDuration: TimeInterval = demoRingSeconds

    private var overlayTween = Tween.fixed(0)
    private var snoozed: UpcomingAlarm?
    private var ticker: Timer?
    private let keepAwake = KeepAwake()
    private let defaults = UserDefaults.standard
    private var loaded = false

    init() {
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: Keys.alarms), let saved = try? decoder.decode([Alarm].self, from: data) {
            alarms = saved
        } else if let data = defaults.data(forKey: Keys.legacyAlarm), let old = try? decoder.decode(Alarm.self, from: data) {
            // Before the list: a single alarm, with Spotify stored inside it.
            alarms = [old]
            if old.spotify.connected { spotifyLink = old.spotify }
        } else {
            alarms = [Alarm()]
        }
        if let data = defaults.data(forKey: Keys.spotify), let link = try? decoder.decode(SpotifyLink.self, from: data) {
            spotifyLink = link
        }
        palette = defaults.string(forKey: Keys.palette).flatMap(LavaPalette.Name.init(rawValue:)) ?? .ember
        demoTimings = defaults.bool(forKey: Keys.demo)
        hdrBoost = defaults.object(forKey: Keys.hdr) as? Bool ?? true
        dimAtNight = defaults.object(forKey: Keys.night) as? Bool ?? true
        loaded = true

        reschedule()
        if defaults.bool(forKey: Keys.armed), upcoming != nil { phase = .armed }
        overlayTween = .fixed(dimTarget)
        save()

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    var anyEnabled: Bool { alarms.contains { $0.enabled } }

    // MARK: - Brightness

    /// Target of the dimming layer for the current state (SPEC §11.3).
    private var dimTarget: Double {
        switch phase {
        case .editing: return anyEnabled || draft != nil ? 0 : 0.45
        case .armed: return 0.93
        case .ringing: return 0
        }
    }

    /// Opacity of the black layer over the lamp: max(1 − brightness, dim).
    func overlayOpacity(at now: Date) -> Double {
        switch phase {
        case .ringing:
            guard let ringStart else { return 0 }
            let b = SunriseCurve.brightness(elapsed: now.timeIntervalSince(ringStart), duration: ringDuration, from: 0.07, delay: 0.5)
            return 1 - b
        case .editing:
            if let previewStart {
                let b = SunriseCurve.brightness(elapsed: now.timeIntervalSince(previewStart), duration: Self.previewSeconds, from: 0)
                return max(1 - b, dimTarget)
            }
            return overlayTween.value(at: now)
        case .armed:
            return overlayTween.value(at: now)
        }
    }

    private static let progressCurve = CubicBezier(0.3, 0.6, 0.4, 1)

    /// Ringing progress bar, 0…1, same 0.5 s delay as the light.
    func ringProgress(at now: Date) -> Double {
        guard let ringStart, ringDuration > 0 else { return 0 }
        let e = (now.timeIntervalSince(ringStart) - 0.5) / ringDuration
        return Self.progressCurve(min(max(e, 0), 1))
    }

    /// Changes state and fades the lamp from wherever it is now to the new target.
    private func transition(_ change: () -> Void) {
        let now = Date()
        let current = overlayOpacity(at: now)
        change()
        overlayTween = Tween(from: current, to: dimTarget, start: now, duration: Self.dimTransition)
        save()
    }

    private func retarget() {
        guard previewStart == nil else { return }
        let now = Date()
        overlayTween = Tween(from: overlayTween.value(at: now), to: dimTarget, start: now, duration: Self.dimTransition)
    }

    // MARK: - List & editor

    func setEnabled(_ id: Alarm.ID, _ on: Bool) {
        guard let i = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[i].enabled = on
    }

    func add() {
        draftIsNew = true
        transition { draft = Alarm() }
    }

    func edit(_ id: Alarm.ID) {
        guard let alarm = alarms.first(where: { $0.id == id }) else { return }
        draftIsNew = false
        transition { draft = alarm }
    }

    /// Save turns the alarm on, like the Clock app.
    func saveDraft() {
        guard var alarm = draft else { return }
        alarm.enabled = true
        if let i = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[i] = alarm
        } else {
            alarms.append(alarm)
        }
        closeEditor()
    }

    /// Back: drop the changes.
    func closeEditor() {
        transition {
            previewStart = nil
            draft = nil
        }
    }

    func deleteDraft() {
        guard let id = draft?.id else { return }
        alarms.removeAll { $0.id == id }
        closeEditor()
    }

    // MARK: - Night mode

    /// Go to sleep: a short countdown and "Night-night", then night mode.
    func startSleepCountdown() {
        guard upcoming != nil, !sleepToastVisible else { return }
        transition {
            previewStart = nil
            draft = nil
        }
        sleepStart = Date()
        sleepToastVisible = true
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.finishSleepCountdown() }
        }
        sleepWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.sleepCountdownSeconds + Self.nightNightSeconds, execute: work)
    }

    func cancelSleepCountdown() {
        sleepWork?.cancel()
        sleepWork = nil
        sleepToastVisible = false
    }

    private func finishSleepCountdown() {
        sleepWork = nil
        sleepToastVisible = false
        goToSleep()
    }

    func goToSleep() {
        guard upcoming != nil else { return }
        transition {
            previewStart = nil
            draft = nil
            phase = .armed
        }
    }

    /// Armed pill → back to the list.
    func wake() {
        transition { phase = .editing }
    }

    /// × on the armed pill: turn off the alarm it shows, back to the list.
    func turnOffUpcoming() {
        if let id = upcoming?.alarm.id { setEnabled(id, false) }
        snoozed = nil
        transition { phase = .editing }
        reschedule()
    }

    // MARK: - Ringing

    /// `quick`: debug ring — a 10 s sunrise whatever the alarm's duration.
    func ring(_ alarm: Alarm? = nil, at now: Date = Date(), quick: Bool = false) {
        guard phase != .ringing else { return }
        cancelSleepCountdown()
        let alarm = alarm ?? upcoming?.alarm ?? draft ?? alarms.first ?? Alarm()
        previewStart = nil
        snoozed = nil
        ringingAlarm = alarm
        ringStart = now
        ringDuration = quick || demoTimings ? Self.demoRingSeconds : Double(alarm.sunriseMinutes) * 60
        phase = .ringing
        save()
        reschedule(after: now)
        if spotifyLink.connected { spotify.startAlarm(uri: spotifyLink.uri) }
    }

    /// Awake: back to the list with the lamp and the screen at full light.
    /// The alarm stays on for its next day; a one-off alarm switches itself off.
    func stop() {
        spotify.stopAlarm()
        // Keep the backlight where the sunrise left it instead of fading back to the evening level.
        Backlight.shared.keepCurrent()
        if ringingAlarm.isOnce { setEnabled(ringingAlarm.id, false) }
        transition {
            draft = nil
            phase = .editing
        }
        reschedule()
    }

    /// Back to night mode; the same alarm rings again after the snooze.
    func snooze(now: Date = Date()) {
        spotify.stopAlarm()
        let delay = demoTimings ? Self.demoSnoozeSeconds : Self.snoozeSeconds
        snoozed = UpcomingAlarm(alarm: ringingAlarm, date: now.addingTimeInterval(delay), isSnooze: true)
        transition { phase = .armed }
        reschedule()
    }

    func togglePreview() {
        if previewStart != nil {
            transition { previewStart = nil }
        } else {
            previewStart = Date()
        }
    }

    // MARK: - Spotify

    /// `link`: a Spotify share link / URI (artist, playlist, album, track…), or empty to resume
    /// whatever played last. An artist plays from the top of their page (popular tracks).
    func connectSpotify(link: String) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if SpotifyURI.isShortLink(trimmed) {
            spotifyBusy = true
            spotifyError = nil
            Spotify.resolveShortLink(trimmed) { [weak self] uri in
                guard let self else { return }
                guard let uri else {
                    self.spotifyBusy = false
                    self.spotifyError = "Couldn't open that short link. Copy the link from the Spotify desktop app instead."
                    return
                }
                self.connectSpotify(link: uri)
            }
            return
        }
        let uri = trimmed.isEmpty ? nil : SpotifyURI.parse(trimmed)
        if !trimmed.isEmpty, uri == nil {
            spotifyError = "That doesn't look like a Spotify link."
            return
        }
        spotifyBusy = true
        spotifyError = nil
        spotify.connect { [weak self] failure in
            guard let self else { return }
            self.spotifyBusy = false
            if let failure {
                self.spotifyError = failure.message
                return
            }
            self.spotifyLink = SpotifyLink(connected: true, playlist: "", uri: uri)
            guard let uri else { return }
            Spotify.fetchTitle(for: uri) { [weak self] title in
                guard let self, self.spotifyLink.uri == uri else { return }
                self.spotifyLink.playlist = title ?? "your Spotify link"
            }
        }
    }

    func disconnectSpotify() {
        spotifyLink = SpotifyLink()
        spotifyError = nil
    }

    func clearSpotifyError() { spotifyError = nil }

    // MARK: - Scheduling

    private func alarmsChanged() {
        guard loaded else { return }
        reschedule()
        if phase == .editing { retarget() }
        save()
    }

    private func reschedule(after now: Date = Date()) {
        let regular = AlarmSchedule.next(in: alarms, after: now).map { UpcomingAlarm(alarm: $0.alarm, date: $0.date) }
        if let snoozed, regular.map({ snoozed.date <= $0.date }) ?? true {
            upcoming = snoozed
        } else {
            upcoming = regular
        }
        updateKeepAwake()
    }

    private func updateKeepAwake() {
        switch phase {
        case .armed, .ringing: keepAwake.set(.display)
        case .editing: keepAwake.set(upcoming != nil && license.alarmsMayRing ? .system : .none)
        }
    }

    func tick() {
        let now = Date()
        // Spotify volume follows the light: 0 at first light, 75 at full sunrise.
        if phase == .ringing, let ringStart {
            let b = SunriseCurve.brightness(elapsed: now.timeIntervalSince(ringStart), duration: ringDuration, from: 0.07, delay: 0.5)
            spotify.setVolume(Int((Self.spotifyMaxVolume * (b - 0.07) / 0.93).rounded()))
        }
        if let previewStart, now.timeIntervalSince(previewStart) > Self.previewSeconds + 1.5 {
            transition { self.previewStart = nil }
        }
        updateKeepAwake()
        // Before a trial/license (or a day after the trial ended) nothing rings.
        guard phase != .ringing, license.alarmsMayRing, let due = upcoming, now >= due.date else { return }
        let isSnooze = snoozed != nil && due.date == snoozed?.date
        snoozed = nil
        // Woke up long after the alarm (e.g. the Mac slept through it) — skip to the next one.
        if now.timeIntervalSince(due.date) < 3600 {
            ring(due.alarm, at: now)
        } else {
            if !isSnooze, due.alarm.isOnce { setEnabled(due.alarm.id, false) }
            reschedule(after: now)
        }
    }

    // MARK: - Persistence

    private enum Keys {
        static let alarms = "alarms"
        static let legacyAlarm = "alarm"
        static let spotify = "spotify"
        static let armed = "armed"
        static let palette = "palette"
        static let demo = "demoTimings"
        static let hdr = "hdrBoost"
        static let night = "dimAtNight"
    }

    private func save() {
        guard loaded else { return }
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(alarms) { defaults.set(data, forKey: Keys.alarms) }
        if let data = try? encoder.encode(spotifyLink) { defaults.set(data, forKey: Keys.spotify) }
        defaults.set(phase != .editing, forKey: Keys.armed)
        defaults.set(palette.rawValue, forKey: Keys.palette)
        defaults.set(demoTimings, forKey: Keys.demo)
        defaults.set(hdrBoost, forKey: Keys.hdr)
        defaults.set(dimAtNight, forKey: Keys.night)
        updateKeepAwake()
    }
}
