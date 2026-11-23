import Charts
import SwiftUI

/// Ansicht „Statistik“ (Spec 5, Screen 2): Summen, 7-Tage-Balken,
/// 30-Tage-Linie, Tagesziel-Linie. Kopf und Segmentschalter liegen in
/// `RootView`.
///
/// Die Summen für heute/Woche/Monat kommen aus `?action=stats`; die Tagesreihe
/// rechnet die App aus den letzten Einträgen (`?action=entries&limit=500`),
/// weil die API keine Tagesreihe liefert.
struct StatsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let user = store.selectedUser {
                content(for: user)
            } else {
                MhLeer("Noch keine Auswertung. Lege zuerst einen Nutzer an und trage etwas ein.")
            }
        }
    }

    @ViewBuilder
    private func content(for user: TrinkUser) -> some View {
        let perDay = Self.sumPerDay(store.historyEntries)
        let ziel = user.tageszielMl
        let woche = DayValue.lastDays(7, perDay: perDay)
        let monat = DayValue.lastDays(30, perDay: perDay)

        OfflineBanner(isOffline: store.isOffline, pendingCount: store.pendingCount) {
            Task { await store.flushQueue() }
        }

        if store.users.count > 1 {
            Abschnittskopf("Nutzer")
            FlowLayout {
                ForEach(store.users) { other in
                    MhAuswahl(other.name, gewaehlt: other.id == user.id) {
                        Task { await store.selectUser(other.id) }
                    }
                }
            }
            .padding(.bottom, Mh.abstand2)
        }
        Hinweistext(ziel == 0 ? "\(user.name) · kein Tagesziel festgelegt" : "\(user.name) · Tagesziel \(ziel) ml")
            .padding(.bottom, Mh.abstand5)

        HStack(alignment: .top, spacing: Mh.abstand3) {
            Summe(label: "Heute", stats: store.stats.today)
            Summe(label: "Woche", stats: store.stats.week)
            Summe(label: "Monat", stats: store.stats.month)
        }
        .padding(.bottom, Mh.abstand6)
        MhTrennlinie()

        VStack(alignment: .leading, spacing: 0) {
            DiagrammKopf(titel: "Letzte 7 Tage", tage: woche)
            WeekBars(days: woche, tageszielMl: ziel).padding(.top, Mh.abstand4)
            Legende(tageszielMl: ziel, mitBalken: true).padding(.top, Mh.abstand3)
        }
        .padding(.top, Mh.abstand6)

        VStack(alignment: .leading, spacing: 0) {
            DiagrammKopf(titel: "Letzte 30 Tage", tage: monat)
            MonthLine(days: monat, tageszielMl: ziel).padding(.top, Mh.abstand4)
            Legende(tageszielMl: ziel, mitBalken: false).padding(.top, Mh.abstand3)
        }
        .padding(.top, Mh.abstand8)

        Hinweistext(ziel == 0
            ? "Kein Tagesziel gesetzt. Die Ziel-Linie erscheint, sobald eines hinterlegt ist. Das Tagesziel änderst du unter Nutzer."
            : "Tage ohne Einträge zählen mit 0 ml. Das Tagesziel änderst du unter Nutzer.")
            .padding(.top, Mh.abstand8)
    }

    /// Tagessummen nach Berliner Kalendertag.
    static func sumPerDay(_ entries: [TrinkEntry]) -> [String: Int] {
        var perDay: [String: Int] = [:]
        for entry in entries {
            perDay[BerlinTime.dateKey(entry.createdAt), default: 0] += entry.mengeMl
        }
        return perDay
    }
}

struct DayValue: Identifiable {
    let date: Date
    let key: String
    let ml: Int
    var id: String { key }

    /// Kurzform des Wochentags — innerhalb von 7 Tagen eindeutig, daher als X-Achse nutzbar.
    var weekday: String { BerlinTime.formatWeekday(date) }

    static func lastDays(_ count: Int, perDay: [String: Int], now: Date = Date()) -> [DayValue] {
        (0..<count).reversed().map { offset in
            let date = now.addingTimeInterval(-Double(offset) * 86_400)
            let key = BerlinTime.dateKey(date)
            return DayValue(date: date, key: key, ml: perDay[key] ?? 0)
        }
    }
}

/// Summe eines Zeitraums (`.stat-value` + `.stat-label`): Zahl dünn in
/// Textfarbe, Einheit klein, Bezeichnung darunter.
private struct Summe: View {
    let label: String
    let stats: PeriodStats

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: "\(stats.ml)")
                    .mhText(.number)
                    .foregroundStyle(Mh.textStrong)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("ml")
                    .mhText(.small)
                    .foregroundStyle(Mh.textSecondary)
            }
            Text(verbatim: "\(label) · \(stats.anzahl)×")
                .mhText(.small)
                .monospacedDigit()
                .foregroundStyle(Mh.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct DiagrammKopf: View {
    let titel: String
    let tage: [DayValue]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Mh.abstand3) {
            Text(titel)
                .mhText(.h3)
                .foregroundStyle(Mh.textStrong)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: "\(BerlinTime.formatDayMonth(tage.first?.date ?? Date())) – \(BerlinTime.formatDayMonth(tage.last?.date ?? Date()))")
                .mhText(.small)
                .monospacedDigit()
                .foregroundStyle(Mh.textSecondary)
        }
    }
}

/// Legende unter einem Diagramm: Punkte immer mit Text daneben.
private struct Legende: View {
    let tageszielMl: Int
    let mitBalken: Bool

    var body: some View {
        if tageszielMl > 0 {
            FlowLayout(spacing: Mh.abstand4) {
                if mitBalken {
                    eintrag(Mh.data1, "Tagesmenge")
                    eintrag(Mh.data2, "Ziel erreicht")
                }
                HStack(spacing: 6) {
                    ZielStrich().frame(width: 16, height: 2)
                    Text(verbatim: "Tagesziel \(tageszielMl) ml")
                }
            }
            .mhText(.small)
            .foregroundStyle(Mh.textSecondary)
            .accessibilityElement(children: .combine)
        }
    }

    private func eintrag(_ farbe: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            MhPunkt(farbe: farbe, groesse: 8)
            Text(text)
        }
    }
}

/// Gestrichelte Ziel-Linie als kleines Legendenzeichen.
private struct ZielStrich: View {
    var body: some View {
        GeometryReader { geo in
            Path { pfad in
                pfad.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                pfad.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
            }
            .stroke(Mh.textTertiary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        .accessibilityHidden(true)
    }
}

private let achsenSchrift = Font.custom(MhSchrift.regular, size: 12, relativeTo: .caption)

private struct WeekBars: View {
    let days: [DayValue]
    let tageszielMl: Int

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(x: .value("Tag", day.weekday), y: .value("ml", day.ml), width: .ratio(0.6))
                    .foregroundStyle(tageszielMl > 0 && day.ml >= tageszielMl ? Mh.data2 : Mh.data1)
                    .cornerRadius(4)
                    .annotation(position: .top, spacing: Mh.abstand1) {
                        Text(verbatim: "\(day.ml)")
                            .font(achsenSchrift)
                            .monospacedDigit()
                            .foregroundStyle(Mh.text)
                    }
            }
            if tageszielMl > 0 {
                RuleMark(y: .value("Ziel", tageszielMl))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                    .foregroundStyle(Mh.textTertiary)
            }
        }
        .chartXScale(domain: days.map(\.weekday))
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(achsenSchrift)
                    .foregroundStyle(Mh.textSecondary)
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...Double(max(days.map(\.ml).max() ?? 0, tageszielMl, 1)) * 1.15)
        .frame(height: 190)
    }
}

private struct MonthLine: View {
    let days: [DayValue]
    let tageszielMl: Int

    var body: some View {
        Chart {
            ForEach(days) { day in
                AreaMark(x: .value("Tag", day.date, unit: .day), y: .value("ml", day.ml))
                    .foregroundStyle(Mh.data1.opacity(0.22))
                    .interpolationMethod(.linear)
                LineMark(x: .value("Tag", day.date, unit: .day), y: .value("ml", day.ml))
                    .foregroundStyle(Mh.data1)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)
            }
            if tageszielMl > 0 {
                // Gestrichelt, damit sich die Ziel-Linie von der Tageslinie absetzt.
                RuleMark(y: .value("Ziel", tageszielMl))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                    .foregroundStyle(Mh.textTertiary)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Mh.border)
                AxisValueLabel().foregroundStyle(Mh.textSecondary).font(achsenSchrift)
            }
        }
        .chartYScale(domain: 0...Double(max(days.map(\.ml).max() ?? 0, tageszielMl, 1)) * 1.1)
        .frame(height: 180)
    }
}
