import Foundation
import Testing
@testable import TrinkTracker

struct ModelsTests {
    @Test func boolAusVerschiedenenFormen() {
        #expect(asBool(1) == true)
        #expect(asBool(0) == false)
        #expect(asBool("true") == true)
        #expect(asBool("1") == true)
        #expect(asBool("0") == false)
        #expect(asBool(true) == true)
        #expect(asBool(nil) == false)
    }

    @Test func intAusStringUndDouble() {
        #expect(asInt("42") == 42)
        #expect(asInt(" 7 ") == 7)
        #expect(asInt(3.6) == 4)
        #expect(asInt("x", fallback: 9) == 9)
        #expect(asIntOrNull(nil) == nil)
        #expect(asIntOrNull(NSNull()) == nil)
        #expect(asIntOrNull("12") == 12)
    }

    @Test func todayStatsOhneTageszielHatKeinenFortschritt() {
        let stats = TodayStats(json: ["ml": 500, "anzahl": 2, "tagesziel_ml": 0, "ziel_fortschritt_pct": 25, "ziel_erreicht": false])
        #expect(stats.fortschrittPct == nil)
        #expect(stats.zielErreicht == false)
        #expect(stats.tageszielMl == 0)
    }

    @Test func todayStatsZielErreichtAuchAls1() {
        let stats = TodayStats(json: ["ml": "2100", "anzahl": "5", "tagesziel_ml": "2000", "ziel_fortschritt_pct": "105", "ziel_erreicht": 1])
        #expect(stats.ml == 2100)
        #expect(stats.fortschrittPct == 105)
        #expect(stats.zielErreicht == true)
    }

    @Test func serverzeitOhneZoneWirdAlsUTCGelesen() {
        let date = parseServerTime("2026-07-14 22:30:00")
        #expect(date == BerlinTime.utcDate(2026, 7, 14, 22, 30))
        #expect(parseServerTime("2026-07-14T22:30:00.000Z") == date)
        #expect(parseServerTime("2026-07-14T22:30") == date)
    }

    @Test func eintragMitNegativerIdGiltAlsAusstehend() {
        let entry = TrinkEntry(json: ["id": -3, "user_id": 1, "getraenk": "Wasser", "menge_ml": 250, "create_time": "2026-07-14 22:30:00"])
        #expect(entry.isPending)
        #expect(entry.mengeMl == 250)
        let roundTrip = TrinkEntry(json: entry.json)
        #expect(roundTrip == entry)
    }

    @Test func statsBundleLiestAlleDreiPerioden() {
        let bundle = StatsBundle(json: [
            "periods": [
                "today": ["ml": 500, "anzahl": 2],
                "week": ["ml": "3000", "anzahl": "12"],
                "month": ["ml": 9000, "anzahl": 40],
            ],
        ])
        #expect(bundle.today.ml == 500)
        #expect(bundle.week.anzahl == 12)
        #expect(bundle.month.ml == 9000)
        #expect(StatsBundle(json: bundle.json) == bundle)
    }
}
