import Foundation

/// Tagesgrenzen rechnet der Server in Europe/Berlin (Spec 2 „Server-Konventionen"),
/// gespeichert wird UTC. Damit die App dieselben Grenzen zieht — auch wenn das
/// Gerät in einer anderen Zone steht — rechnen wir Berlin hier selbst.
///
/// Regel (EU-Richtlinie 2000/84/EG): MEZ = UTC+1, MESZ = UTC+2 vom letzten
/// Sonntag im März 01:00 UTC bis zum letzten Sonntag im Oktober 01:00 UTC.
enum BerlinTime {
    static let cet: TimeInterval = 3600
    static let cest: TimeInterval = 7200

    /// Gregorianischer Kalender in UTC, Montag als Wochenbeginn.
    static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }()

    static func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    private static func lastSundayUtc(year: Int, month: Int, hourUtc: Int) -> Date {
        // Letzter Tag des Monats, dann auf den Sonntag zurückgehen.
        let firstOfNext = utcDate(month == 12 ? year + 1 : year, month == 12 ? 1 : month + 1, 1)
        let lastDay = utcCalendar.date(byAdding: .day, value: -1, to: firstOfNext)!
        let weekday = utcCalendar.component(.weekday, from: lastDay) // Sonntag == 1
        let sunday = utcCalendar.date(byAdding: .day, value: -(weekday - 1), to: lastDay)!
        let comps = utcCalendar.dateComponents([.year, .month, .day], from: sunday)
        return utcDate(comps.year!, comps.month!, comps.day!, hourUtc)
    }

    /// Offset von Berlin gegenüber UTC zum angegebenen Zeitpunkt.
    static func offset(at instant: Date) -> TimeInterval {
        let year = utcCalendar.component(.year, from: instant)
        let start = lastSundayUtc(year: year, month: 3, hourUtc: 1)
        let end = lastSundayUtc(year: year, month: 10, hourUtc: 1)
        let summer = instant >= start && instant < end
        return summer ? cest : cet
    }

    /// UTC-Zeitpunkt als Berliner Wanduhrzeit — als „naives" Date in UTC-Form,
    /// damit Komponentenzugriffe über `utcCalendar` direkt Berliner Werte liefern.
    static func toBerlin(_ instant: Date) -> Date {
        instant.addingTimeInterval(offset(at: instant))
    }

    /// Berliner Wanduhrzeit (naiv, UTC-Form) zurück nach UTC.
    static func berlinToUtc(_ wallClock: Date) -> Date {
        // Erst mit dem Offset des Rohwerts schätzen, dann mit dem Offset des
        // Ergebnisses korrigieren — das trifft auch nahe der Umstellung.
        let guess = wallClock.addingTimeInterval(-offset(at: wallClock))
        return wallClock.addingTimeInterval(-offset(at: guess))
    }

    static func components(_ instant: Date) -> DateComponents {
        utcCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: toBerlin(instant))
    }

    /// Beginn des Berliner Tages, in dem `instant` liegt — als UTC-Zeitpunkt.
    static func dayStartUtc(_ instant: Date) -> Date {
        let b = components(instant)
        return berlinToUtc(utcDate(b.year!, b.month!, b.day!))
    }

    /// Beginn der laufenden Berliner Woche (Montag) als UTC-Zeitpunkt.
    static func weekStartUtc(_ instant: Date) -> Date {
        let b = components(instant)
        let mondayBased = (b.weekday! + 5) % 7 // Mo == 0 … So == 6
        let dayStart = utcDate(b.year!, b.month!, b.day!)
        let monday = utcCalendar.date(byAdding: .day, value: -mondayBased, to: dayStart)!
        return berlinToUtc(monday)
    }

    /// Beginn des laufenden Berliner Monats als UTC-Zeitpunkt.
    static func monthStartUtc(_ instant: Date) -> Date {
        let b = components(instant)
        return berlinToUtc(utcDate(b.year!, b.month!, 1))
    }

    /// Berliner Kalendertag als `yyyy-MM-dd`.
    static func dateKey(_ instant: Date) -> String {
        let b = components(instant)
        return String(format: "%04d-%02d-%02d", b.year!, b.month!, b.day!)
    }

    /// Format für `create_time` beim Server: `Y-m-dTH:i` in Berliner Zeit (Spec 2).
    static func formatCreateTime(_ instant: Date) -> String {
        let b = components(instant)
        return String(format: "%04d-%02d-%02dT%02d:%02d", b.year!, b.month!, b.day!, b.hour!, b.minute!)
    }

    /// `HH:mm` in Berliner Zeit, für die Anzeige.
    static func formatTime(_ instant: Date) -> String {
        let b = components(instant)
        return String(format: "%02d:%02d", b.hour!, b.minute!)
    }

    /// `dd.MM.` in Berliner Zeit, für die Anzeige.
    static func formatDayMonth(_ instant: Date) -> String {
        let b = components(instant)
        return String(format: "%02d.%02d.", b.day!, b.month!)
    }

    static let weekdayShort = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    static func formatWeekday(_ instant: Date) -> String {
        let weekday = components(instant).weekday! // So == 1
        return weekdayShort[(weekday + 5) % 7]
    }
}
