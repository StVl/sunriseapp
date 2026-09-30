import XCTest
@testable import SunriseCore

final class DaysLabelTests: XCTestCase {
    private func days(_ idx: [Int]) -> [Bool] { (0..<7).map { idx.contains($0) } }

    func testNamedSets() {
        XCTAssertEqual(DaysLabel.make(days([0, 1, 2, 3, 4, 5, 6])), "Every day")
        XCTAssertEqual(DaysLabel.make(days([])), "Once")
        XCTAssertEqual(DaysLabel.make(days([0, 1, 2, 3, 4])), "Weekdays")
        XCTAssertEqual(DaysLabel.make(days([5, 6])), "Weekends")
    }

    func testRangesAndSingles() {
        XCTAssertEqual(DaysLabel.make(days([0, 1, 2, 3])), "Mon–Thu")
        XCTAssertEqual(DaysLabel.make(days([0, 1, 2, 5])), "Mon–Wed, Sat")
        XCTAssertEqual(DaysLabel.make(days([0, 1])), "Mon, Tue")
        XCTAssertEqual(DaysLabel.make(days([0, 2, 4])), "Mon, Wed, Fri")
    }
}

final class AlarmTextTests: XCTestCase {
    func testFullLightWrapsMidnight() {
        let a = Alarm(hour: 23, minute: 50, sunriseMinutes: 30)
        XCTAssertEqual(a.timeText, "23:50")
        XCTAssertEqual(a.lightStartText, "23:44")
        XCTAssertEqual(a.fullLightText, "00:14")
    }

    func testDefaults() {
        let a = Alarm()
        XCTAssertEqual(a.timeText, "07:00")
        XCTAssertEqual(a.lightStartText, "06:54")
        XCTAssertEqual(a.fullLightText, "07:24")
        XCTAssertEqual(a.daysLabel, "Weekdays")
    }

    /// 7:00 with a 10-minute sunrise: light from 06:58, full at 07:08.
    func testLightStartsTwoTenthsEarly() {
        let a = Alarm(hour: 7, minute: 0, sunriseMinutes: 10)
        XCTAssertEqual(a.leadSeconds, 120)
        XCTAssertEqual(a.lightStartText, "06:58")
        XCTAssertEqual(a.fullLightText, "07:08")
        // 7 min → 84 s lead: 06:58:36, shown as 06:58.
        XCTAssertEqual(Alarm(hour: 7, minute: 0, sunriseMinutes: 7).lightStartText, "06:58")
        XCTAssertEqual(Alarm(hour: 0, minute: 0, sunriseMinutes: 5).lightStartText, "23:59")
    }

    func testSavedSunriseOver30IsCapped() throws {
        let json = #"{"hour":7,"minute":0,"sunriseMinutes":60}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(Alarm.self, from: json).sunriseMinutes, 30)
    }
}

final class ScheduleTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    // 2026-10-02 is a Friday. Default sunrise is 30 min → the light starts 6 min early.
    func testWeekdayAlarmLaterToday() {
        let a = Alarm(hour: 7, minute: 0)
        XCTAssertEqual(AlarmSchedule.nextFire(for: a, after: date(2026, 10, 2, 6, 0), calendar: cal), date(2026, 10, 2, 6, 54))
    }

    func testWeekdayAlarmSkipsWeekend() {
        let a = Alarm(hour: 7, minute: 0)
        // Friday after the light started → Monday 2026-10-05.
        XCTAssertEqual(AlarmSchedule.nextFire(for: a, after: date(2026, 10, 2, 6, 55), calendar: cal), date(2026, 10, 5, 6, 54))
    }

    func testOnceAlarmRollsToTomorrow() {
        let a = Alarm(hour: 7, minute: 0, days: Array(repeating: false, count: 7))
        XCTAssertEqual(AlarmSchedule.nextFire(for: a, after: date(2026, 10, 3, 9, 0), calendar: cal), date(2026, 10, 4, 6, 54))
    }

    /// Days belong to the alarm time: Monday 00:05 starts its light late on Sunday.
    func testLeadCrossesMidnightButKeepsTheDay() {
        let mondays = Alarm(hour: 0, minute: 5, days: [true, false, false, false, false, false, false], sunriseMinutes: 30)
        // Saturday noon → Sunday 23:59 (for Monday 00:05), not Monday 23:59.
        XCTAssertEqual(AlarmSchedule.nextFire(for: mondays, after: date(2026, 10, 3, 12, 0), calendar: cal), date(2026, 10, 4, 23, 59))
    }

    func testEarliestAcrossList() {
        let weekdays = Alarm(hour: 7, minute: 0)
        let weekend = Alarm(hour: 9, minute: 30, days: [false, false, false, false, false, true, true])
        let off = Alarm(hour: 6, minute: 0, enabled: false)
        // Friday evening → Saturday 09:30 beats Monday 07:00; the disabled 06:00 is ignored.
        let next = AlarmSchedule.next(in: [weekdays, weekend, off], after: date(2026, 10, 2, 20, 0), calendar: cal)
        XCTAssertEqual(next?.alarm.id, weekend.id)
        XCTAssertEqual(next?.date, date(2026, 10, 3, 9, 24)) // 30 min sunrise → 6 min early
        XCTAssertNil(AlarmSchedule.next(in: [off], after: date(2026, 10, 2, 20, 0), calendar: cal))
    }

    func testNextLabel() {
        let now = date(2026, 10, 2, 20, 0) // Friday
        XCTAssertEqual(AlarmSchedule.label(for: date(2026, 10, 2, 22, 15), now: now, calendar: cal), "Today 22:15")
        XCTAssertEqual(AlarmSchedule.label(for: date(2026, 10, 3, 7, 0), now: now, calendar: cal), "Tomorrow 07:00")
        XCTAssertEqual(AlarmSchedule.label(for: date(2026, 10, 5, 7, 0), now: now, calendar: cal), "Mon 07:00")
    }

    func testDisabledHasNoFire() {
        let a = Alarm(enabled: false)
        XCTAssertNil(AlarmSchedule.nextFire(for: a, after: date(2026, 10, 2, 6, 0), calendar: cal))
    }
}

final class CurveTests: XCTestCase {
    func testRingBrightness() {
        // 0.5 s delay, then 0.07 → 1.
        XCTAssertEqual(SunriseCurve.brightness(elapsed: 0, duration: 10, from: 0.07, delay: 0.5), 0.07, accuracy: 1e-9)
        XCTAssertEqual(SunriseCurve.brightness(elapsed: 10.5, duration: 10, from: 0.07, delay: 0.5), 1, accuracy: 1e-9)
        XCTAssertEqual(SunriseCurve.brightness(elapsed: 5.5, duration: 10, from: 0.07, delay: 0.5), 0.07 + 0.93 * 0.75, accuracy: 1e-9)
    }

    func testBezier() {
        let b = CubicBezier(0.3, 0.6, 0.4, 1)
        XCTAssertEqual(b(0), 0)
        XCTAssertEqual(b(1), 1)
        var prev = 0.0
        for i in 1...100 {
            let v = b(Double(i) / 100)
            XCTAssertGreaterThanOrEqual(v, prev)
            prev = v
        }
        XCTAssertEqual(CubicBezier(0, 0, 1, 1)(0.3), 0.3, accuracy: 1e-4)
    }
}

final class SpotifyURITests: XCTestCase {
    func testShareLinks() {
        XCTAssertEqual(SpotifyURI.parse("https://open.spotify.com/playlist/37i9dQZF1DX0SM0LYsmbMT?si=abc123"), "spotify:playlist:37i9dQZF1DX0SM0LYsmbMT")
        XCTAssertEqual(SpotifyURI.parse("  https://open.spotify.com/intl-de/album/4aawyAB9vmqN3uQ7FjRGTy\n"), "spotify:album:4aawyAB9vmqN3uQ7FjRGTy")
        XCTAssertEqual(SpotifyURI.parse("https://open.spotify.com/track/11dFghVXANMlKmJXsNCbNl"), "spotify:track:11dFghVXANMlKmJXsNCbNl")
    }

    func testArtistLinks() {
        XCTAssertEqual(SpotifyURI.parse("https://open.spotify.com/artist/4Z8W4fKeB5YxbusRsdQVPb?si=abc"), "spotify:artist:4Z8W4fKeB5YxbusRsdQVPb")
        XCTAssertEqual(SpotifyURI.parse("https://open.spotify.com/intl-ru/artist/4Z8W4fKeB5YxbusRsdQVPb"), "spotify:artist:4Z8W4fKeB5YxbusRsdQVPb")
        XCTAssertEqual(SpotifyURI.parse("https://open.spotify.com/artist/53XhwfbYqKCa1cC15pYq2q?si=c7raW-21Tb-x2WNUkFshnw"), "spotify:artist:53XhwfbYqKCa1cC15pYq2q")
    }

    func testShortLinks() {
        XCTAssertTrue(SpotifyURI.isShortLink("https://spotify.link/AbCdEf123"))
        XCTAssertFalse(SpotifyURI.isShortLink("https://open.spotify.com/artist/4Z8W4fKeB5YxbusRsdQVPb"))
        let page = #"<html><meta property="og:url" content="https://open.spotify.com/intl-ru/artist/4Z8W4fKeB5YxbusRsdQVPb?si=x"></html>"#
        XCTAssertEqual(SpotifyURI.find(in: page), "spotify:artist:4Z8W4fKeB5YxbusRsdQVPb")
        XCTAssertNil(SpotifyURI.find(in: "https://spotify.link/AbCdEf123"))
    }

    func testURIs() {
        XCTAssertEqual(SpotifyURI.parse("spotify:playlist:37i9dQZF1DX0SM0LYsmbMT"), "spotify:playlist:37i9dQZF1DX0SM0LYsmbMT")
        XCTAssertNil(SpotifyURI.parse("spotify:user:abc"))
    }

    func testRejects() {
        XCTAssertNil(SpotifyURI.parse(""))
        XCTAssertNil(SpotifyURI.parse("https://example.com/playlist/abc"))
        XCTAssertNil(SpotifyURI.parse("https://open.spotify.com/"))
        XCTAssertNil(SpotifyURI.parse("morning light"))
    }

    func testOldSavedAlarmGetsAnID() throws {
        let old = #"{"hour":8,"minute":5,"days":[true,true,true,true,true,false,false],"sunriseMinutes":5,"enabled":false,"spotify":{"connected":false,"playlist":"Morning Light"}}"#.data(using: .utf8)!
        let a = try JSONDecoder().decode(Alarm.self, from: old)
        XCTAssertEqual(a.timeText, "08:05")
        XCTAssertEqual(a.sunriseMinutes, 5)
        XCTAssertFalse(a.enabled)
        let again = try JSONDecoder().decode(Alarm.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(again.id, a.id)
    }

    func testOldSavedLinkStillDecodes() throws {
        let old = #"{"connected":true,"playlist":"Morning Light"}"#.data(using: .utf8)!
        let link = try JSONDecoder().decode(SpotifyLink.self, from: old)
        XCTAssertTrue(link.connected)
        XCTAssertNil(link.uri)
    }
}

final class LicensePolicyTests: XCTestCase {
    private let day: TimeInterval = 24 * 3600
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testUndecidedUntilTrialOrLicense() {
        XCTAssertEqual(LicensePolicy.state(trialStart: nil, license: nil, now: start), .undecided)
        XCTAssertFalse(LicenseState.undecided.canUseApp)
        XCTAssertFalse(LicensePolicy.alarmsMayRing(.undecided, now: start))
    }

    func testTrialCountsDown() {
        let ends = start.addingTimeInterval(30 * day)
        XCTAssertEqual(LicensePolicy.state(trialStart: start, license: nil, now: start), .trial(daysLeft: 30, endsAt: ends))
        XCTAssertEqual(LicensePolicy.state(trialStart: start, license: nil, now: start.addingTimeInterval(7.5 * day)), .trial(daysLeft: 23, endsAt: ends))
        // Last hours still show "1 day".
        XCTAssertEqual(LicensePolicy.state(trialStart: start, license: nil, now: ends.addingTimeInterval(-60)), .trial(daysLeft: 1, endsAt: ends))
        // Clock moved back before the start: never more than 30.
        XCTAssertEqual(LicensePolicy.state(trialStart: start, license: nil, now: start.addingTimeInterval(-5 * day)), .trial(daysLeft: 30, endsAt: ends))
    }

    func testExpiryAndGrace() {
        let ends = start.addingTimeInterval(30 * day)
        let state = LicensePolicy.state(trialStart: start, license: nil, now: ends)
        XCTAssertEqual(state, .expired(endedAt: ends))
        XCTAssertFalse(state.canUseApp)
        XCTAssertTrue(LicensePolicy.alarmsMayRing(state, now: ends.addingTimeInterval(8 * 3600)))
        XCTAssertFalse(LicensePolicy.alarmsMayRing(state, now: ends.addingTimeInterval(day + 1)))
    }

    func testLicenseWins() {
        let record = LicenseRecord(key: "SUNRISE-X", activationID: "a", activatedAt: start)
        XCTAssertEqual(LicensePolicy.state(trialStart: start, license: record, now: start.addingTimeInterval(90 * day)), .licensed)
        XCTAssertTrue(LicensePolicy.alarmsMayRing(.licensed, now: start))
    }

    func testRevalidationInterval() {
        var record = LicenseRecord(key: "k", activationID: "a", activatedAt: start)
        XCTAssertFalse(LicensePolicy.needsRevalidation(record, now: start.addingTimeInterval(6 * day)))
        XCTAssertTrue(LicensePolicy.needsRevalidation(record, now: start.addingTimeInterval(7 * day)))
        record.lastValidatedAt = start.addingTimeInterval(6 * day)
        XCTAssertFalse(LicensePolicy.needsRevalidation(record, now: start.addingTimeInterval(8 * day)))
    }

    func testKeyNormalization() {
        XCTAssertEqual(LicensePolicy.normalize("  SUNRISE-02ED-9CBA\n"), "SUNRISE-02ED-9CBA")
        XCTAssertEqual(LicensePolicy.normalize("SUNRISE-02ED -\n9CBA"), "SUNRISE-02ED-9CBA")
    }
}
