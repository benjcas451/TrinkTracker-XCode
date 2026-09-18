import Charts
import SwiftUI

/// Screen 2 „Statistik" (Spec 5): 7-Tage-Balken, 30-Tage-Linie, Tagesziel-Linie.
///
/// Die Summen für heute/Woche/Monat kommen aus `?action=stats`; die Tagesreihe
/// rechnet die App aus den letzten Einträgen (`?action=entries&limit=500`),
/// weil die API keine Tagesreihe liefert.
struct StatsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let user = store.selectedUser {
                    content(for: user, c)
                } else {
                    EmptyHint(title: "Noch keine Auswertung", description: "Lege zuerst einen Nutzer an und trage etwas ein.")
                }
            }
            .padding(TrinkSpacing.lg)
        }
        .background(c.background)
        .refreshable { await store.refresh() }
    }

    @ViewBuilder
    private func content(for user: TrinkUser, _ c: TrinkPalette) -> some View {
        let perDay = Self.sumPerDay(store.historyEntries)
        let ziel = user.tageszielMl

        Text("Statistik").trinkText(.headlineMedium).foregroundStyle(c.textStrong)
        Text(user.name)
            .trinkText(.bodyMedium)
            .foregroundStyle(c.textSecondary)
            .padding(.top, TrinkSpacing.xs)
            .padding(.bottom, TrinkSpacing.lg)

        OfflineBanner(isOffline: store.isOffline, pendingCount: store.pendingCount) {
            Task { await store.flushQueue() }
        }

        HStack(spacing: TrinkSpacing.md) {
            SummaryCard(label: "Heute", stats: store.stats.today)
            SummaryCard(label: "Woche", stats: store.stats.week)
            SummaryCard(label: "Monat", stats: store.stats.month)
        }

        SectionTitle("Letzte 7 Tage").padding(.top, TrinkSpacing.xl)
        TrinkCard { WeekBars(days: DayValue.lastDays(7, perDay: perDay), tageszielMl: ziel) }

        SectionTitle("Letzte 30 Tage").padding(.top, TrinkSpacing.xl)
        TrinkCard { MonthLine(days: DayValue.lastDays(30, perDay: perDay), tageszielMl: ziel) }

        Text(verbatim: ziel == 0
             ? "Kein Tagesziel gesetzt — die Ziel-Linie erscheint, sobald eines hinterlegt ist."
             : "Ziel-Linie: \(ziel) ml")
            .trinkText(.bodySmall)
            .foregroundStyle(c.textSecondary)
            .padding(.top, TrinkSpacing.lg)
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

private struct SummaryCard: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    let stats: PeriodStats

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        TrinkCard(padding: .all(TrinkSpacing.md)) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).trinkText(.bodySmall).foregroundStyle(c.textSecondary)
                Text(verbatim: "\(stats.ml)")
                    .trinkText(.titleLarge, tabular: true)
                    .foregroundStyle(c.accentText)
                    .padding(.top, TrinkSpacing.xs)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(verbatim: "ml · \(stats.anzahl)×").trinkText(.bodySmall).foregroundStyle(c.textSecondary)
            }
        }
    }
}

private struct WeekBars: View {
    @Environment(\.colorScheme) private var scheme
    let days: [DayValue]
    let tageszielMl: Int

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        Chart {
            ForEach(days) { day in
                BarMark(x: .value("Tag", day.weekday), y: .value("ml", day.ml), width: .ratio(0.7))
                    .foregroundStyle(tageszielMl > 0 && day.ml >= tageszielMl ? c.yellow300 : c.green300)
                    .cornerRadius(TrinkRadii.xs)
                    .annotation(position: .top, spacing: TrinkSpacing.xs) {
                        Text(verbatim: "\(day.ml)")
                            .trinkText(.bodySmall, tabular: true)
                            .foregroundStyle(c.textSecondary)
                    }
            }
            if tageszielMl > 0 {
                RuleMark(y: .value("Ziel", tageszielMl))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    .foregroundStyle(c.yellow300)
            }
        }
        .chartXScale(domain: days.map(\.weekday))
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(TrinkTextStyle.bodySmall.font)
                    .foregroundStyle(c.textSecondary)
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...Double(max(days.map(\.ml).max() ?? 0, tageszielMl, 1)) * 1.15)
        .frame(height: 190)
    }
}

private struct MonthLine: View {
    @Environment(\.colorScheme) private var scheme
    let days: [DayValue]
    let tageszielMl: Int

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        VStack(spacing: TrinkSpacing.sm) {
            Chart {
                ForEach(days) { day in
                    AreaMark(x: .value("Tag", day.date, unit: .day), y: .value("ml", day.ml))
                        .foregroundStyle(c.green300.opacity(0.35))
                        .interpolationMethod(.linear)
                    LineMark(x: .value("Tag", day.date, unit: .day), y: .value("ml", day.ml))
                        .foregroundStyle(c.green600)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                        .interpolationMethod(.linear)
                }
                if tageszielMl > 0 {
                    // Gestrichelt, damit sich die Ziel-Linie von der Tageslinie absetzt.
                    RuleMark(y: .value("Ziel", tageszielMl))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                        .foregroundStyle(c.yellow300)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(c.border)
                    AxisValueLabel().foregroundStyle(c.textSecondary).font(TrinkTextStyle.caption.font)
                }
            }
            .chartYScale(domain: 0...Double(max(days.map(\.ml).max() ?? 0, tageszielMl, 1)) * 1.1)
            .frame(height: 180)
            HStack {
                Text(BerlinTime.formatDayMonth(days.first?.date ?? Date()))
                Spacer()
                Text(BerlinTime.formatDayMonth(days.last?.date ?? Date()))
            }
            .trinkText(.bodySmall)
            .foregroundStyle(c.textSecondary)
        }
    }
}
