import Foundation
import Testing
@testable import TrinkTracker

struct BerlinTimeTests {
    private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        BerlinTime.utcDate(y, m, d, h, min)
    }

    @Test func winterIstUTCPlus1() {
        #expect(BerlinTime.offset(at: utc(2026, 1, 15, 12)) == 3600)
    }

    @Test func sommerIstUTCPlus2() {
        #expect(BerlinTime.offset(at: utc(2026, 7, 15, 12)) == 7200)
    }

    @Test func umstellungImMaerzGreiftAb1UhrUTC() {
        // 2026: letzter Sonntag im März ist der 29.
        #expect(BerlinTime.offset(at: utc(2026, 3, 29, 0, 59)) == 3600)
        #expect(BerlinTime.offset(at: utc(2026, 3, 29, 1)) == 7200)
    }

    @Test func umstellungImOktoberEndetUm1UhrUTC() {
        // 2026: letzter Sonntag im Oktober ist der 25.
        #expect(BerlinTime.offset(at: utc(2026, 10, 25, 0, 59)) == 7200)
        #expect(BerlinTime.offset(at: utc(2026, 10, 25, 1)) == 3600)
    }

    @Test func dayStartTrifftMitternachtBerlinerZeit() {
        // 15.07.2026 00:30 Berlin == 14.07.2026 22:30 UTC.
        let instant = utc(2026, 7, 14, 22, 30)
        #expect(BerlinTime.dateKey(instant) == "2026-07-15")
        #expect(BerlinTime.dayStartUtc(instant) == utc(2026, 7, 14, 22))
    }

    @Test func berlinToUtcIstUmkehrungVonToBerlin() {
        for instant in [utc(2026, 1, 1, 8), utc(2026, 6, 30, 23, 45), utc(2026, 12, 31, 22, 15)] {
            #expect(BerlinTime.berlinToUtc(BerlinTime.toBerlin(instant)) == instant)
        }
    }

    @Test func formatCreateTimeLiefertBerlinerZeit() {
        #expect(BerlinTime.formatCreateTime(utc(2026, 7, 14, 22, 30)) == "2026-07-15T00:30")
        #expect(BerlinTime.formatCreateTime(utc(2026, 1, 14, 22, 30)) == "2026-01-14T23:30")
    }

    @Test func wochenstartIstMontagBerlinerZeit() {
        // Mi 15.07.2026 → Montag 13.07.2026 00:00 Berlin == 12.07. 22:00 UTC.
        #expect(BerlinTime.weekStartUtc(utc(2026, 7, 15, 12)) == utc(2026, 7, 12, 22))
        #expect(BerlinTime.monthStartUtc(utc(2026, 7, 15, 12)) == utc(2026, 6, 30, 22))
    }

    @Test func wochentagKuerzel() {
        #expect(BerlinTime.formatWeekday(utc(2026, 7, 15, 12)) == "Mi")
        #expect(BerlinTime.formatWeekday(utc(2026, 7, 19, 12)) == "So")
    }
}
