import SwiftUI
import UIKit

/// Ansicht „Heute“ (Spec 5, Screen 1): Tagesmengen der Familie, Nutzerwahl,
/// Favoriten-Schnellwahl, neuer Eintrag, Liste heute & gestern.
/// Aufbau wie die Web-App (Minze & Honig 2.0); Kopf und Segmentschalter
/// liegen in `RootView`.
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts

    @State private var textPrompt: TextPrompt?
    @State private var confirmPrompt: ConfirmPrompt?
    @State private var showCreateFavorite = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OfflineBanner(isOffline: store.isOffline, pendingCount: store.pendingCount) {
                Task { await store.flushQueue() }
            }

            if let error = store.errorMessage {
                MhHinweis(error, art: .fehler).padding(.bottom, Mh.abstand4)
            }

            if store.users.isEmpty {
                if store.supportsUserManagement {
                    MhLeer("Noch keine Nutzer. Lege für jedes Familienmitglied einen Nutzer an, danach kannst du hier Getränke eintragen.") {
                        Button("Nutzer anlegen") { textPrompt = Dialogs.createUser(store: store, toasts: toasts) }
                            .buttonStyle(.mhHaupt)
                            .padding(.top, Mh.abstand2)
                    }
                } else {
                    MhLeer("Noch keine Nutzer. In diesem Modus legt die Web-App die Nutzer an. Prüfe die Verbindung in den Einstellungen.")
                }
            } else {
                tagesmengen
                nutzerWahl.padding(.top, Mh.abstand8)
                favorites.padding(.top, Mh.abstand8)
                NewEntryForm().padding(.top, Mh.abstand8)
                entryList.padding(.top, Mh.abstand8)
            }

            Hinweistext("Zeiten in Europe/Berlin, mit denselben Tagesgrenzen wie der Server.")
                .padding(.top, Mh.abstand8)
        }
        .textPrompt($textPrompt)
        .confirmPrompt($confirmPrompt)
        .sheet(isPresented: $showCreateFavorite) { CreateFavoriteSheet() }
    }

    // MARK: Tagesmengen

    private var tagesmengen: some View {
        VStack(alignment: .leading, spacing: 0) {
            Abschnittskopf("Heute")
            ForEach(Array(store.users.enumerated()), id: \.element.id) { index, user in
                if index > 0 { MhTrennlinie() }
                TagesZeile(
                    user: user,
                    stats: store.todayByUser[user.id] ?? .empty,
                    selected: user.id == store.selectedUserId,
                    isDefault: store.isDefaultUser(user)
                ) {
                    Task { await store.selectUser(user.id) }
                }
            }
        }
    }

    private var nutzerWahl: some View {
        VStack(alignment: .leading, spacing: 0) {
            Abschnittskopf("Nutzer")
            FlowLayout {
                ForEach(store.users) { user in
                    MhAuswahl(user.name, gewaehlt: user.id == store.selectedUserId) {
                        Task { await store.selectUser(user.id) }
                    }
                }
            }
        }
    }

    // MARK: Schnellwahl (Favoriten)

    private var favorites: some View {
        VStack(alignment: .leading, spacing: 0) {
            Abschnittskopf("Schnellwahl") {
                Button("Hinzufügen") { showCreateFavorite = true }
                    .buttonStyle(.mhText)
            }
            if store.favorites.isEmpty {
                Hinweistext("Noch keine Favoriten. Ein Tipp auf „Hinzufügen“ legt eine Schnellwahl an.")
            } else {
                FlowLayout {
                    ForEach(store.favorites) { favorite in
                        Button {
                            tapFavorite(favorite)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: Mh.abstand2) {
                                Text(favorite.getraenk)
                                    .font(.custom(MhSchrift.medium, size: 16, relativeTo: .body))
                                    .foregroundStyle(Mh.textStrong)
                                Text(verbatim: "\(favorite.mengeMl) ml")
                                    .mhText(.small)
                                    .monospacedDigit()
                                    .foregroundStyle(Mh.textSecondary)
                            }
                        }
                        .buttonStyle(.mhZweit)
                        .accessibilityLabel(Text(verbatim: "\(favorite.getraenk), \(favorite.mengeMl) ml eintragen"))
                        // Gedrückt halten öffnet das Menü — sichtbarer als ein stiller Long-Press.
                        .contextMenu {
                            Button("Jetzt eintragen") { tapFavorite(favorite) }
                            if store.supportsUserManagement {
                                Button("Favorit löschen", role: .destructive) {
                                    confirmPrompt = Dialogs.deleteFavorite(favorite, store: store, toasts: toasts)
                                }
                            } else {
                                Text("Löschen nur mit erweiterten Server-Actions (Einstellungen)")
                            }
                        }
                    }
                }
                Hinweistext(store.supportsUserManagement
                    ? "Ein Tipp trägt den Favoriten sofort ein, gedrückt halten zum Löschen. Alle Favoriten stehen auch unter Nutzer."
                    : "Ein Tipp trägt den Favoriten sofort ein. Löschen bietet die API in diesem Modus nur mit den erweiterten Server-Actions.")
                    .padding(.top, Mh.abstand2)
            }
        }
    }

    private func tapFavorite(_ favorite: TrinkFavorite) {
        // Haptik sofort — der Eintrag soll ohne Umweg losgehen.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            toasts.result(
                await store.addEntry(favorite.getraenk, favorite.mengeMl),
                success: "\(favorite.getraenk) \(favorite.mengeMl) ml eingetragen"
            )
        }
    }

    // MARK: Einträge heute & gestern

    private var entryList: some View {
        let now = Date()
        let todayKey = BerlinTime.dateKey(now)
        let yesterdayKey = BerlinTime.dateKey(now.addingTimeInterval(-86_400))
        // Heute & gestern (Spec 4) — ältere Einträge zeigt die Statistik.
        let visible = store.entries.filter {
            let key = BerlinTime.dateKey($0.createdAt)
            return key == todayKey || key == yesterdayKey
        }
        let heute = visible.filter { BerlinTime.dateKey($0.createdAt) == todayKey }
        let gestern = visible.filter { BerlinTime.dateKey($0.createdAt) == yesterdayKey }

        return VStack(alignment: .leading, spacing: 0) {
            Abschnittskopf("Einträge heute und gestern") {
                Button("Rückgängig") {
                    Task { toasts.result(await store.undoLast(), success: "Letzter Eintrag entfernt") }
                }
                .buttonStyle(.mhLoeschen)
                .disabled(visible.isEmpty)
            }
            if visible.isEmpty {
                MhLeer("Für heute und gestern ist noch nichts erfasst.")
            } else {
                if !heute.isEmpty {
                    TagesGruppe(titel: "Heute · \(BerlinTime.formatDayMonth(now))", eintraege: heute)
                }
                if !gestern.isEmpty {
                    TagesGruppe(titel: "Gestern · \(BerlinTime.formatDayMonth(now.addingTimeInterval(-86_400)))", eintraege: gestern)
                        .padding(.top, heute.isEmpty ? 0 : Mh.abstand5)
                }
            }
        }
    }
}

/// Tagesmenge eines Nutzers (`.tages-zeile`): Name, große Zahl dünn in
/// Textfarbe, Balken zum Tagesziel, darunter Anzahl und Fortschritt.
/// Ein Tipp wählt den Nutzer aus.
private struct TagesZeile: View {
    let user: TrinkUser
    let stats: TodayStats
    let selected: Bool
    let isDefault: Bool
    let onTap: () -> Void

    private var standardText: String {
        isDefault ? "Standardnutzer dieses Geräts" : ""
    }

    private var anzahlText: String {
        stats.anzahl == 1 ? "1 Eintrag" : "\(stats.anzahl) Einträge"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Mh.abstand2) {
                HStack(alignment: .firstTextBaseline, spacing: Mh.abstand3) {
                    HStack(alignment: .center, spacing: Mh.abstand2) {
                        if selected {
                            MhPunkt(farbe: Mh.data1, groesse: 8)
                        }
                        Text(user.name)
                            .font(.custom(MhSchrift.medium, size: 16, relativeTo: .body))
                            .foregroundStyle(Mh.textStrong)
                            .multilineTextAlignment(.leading)
                        if isDefault {
                            MhSymbol("MhStarGefuellt", groesse: Mh.symbolKlein)
                                .foregroundStyle(Mh.textYellow)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(verbatim: "\(stats.ml)")
                            .mhText(.number)
                            .foregroundStyle(Mh.textStrong)
                        Text("ml")
                            .mhText(.small)
                            .foregroundStyle(Mh.textSecondary)
                    }
                    .lineLimit(1)
                }
                if stats.tageszielMl > 0 {
                    MhBalken(
                        anteil: Double(stats.ml) / Double(stats.tageszielMl),
                        farbe: stats.zielErreicht ? Mh.data2 : Mh.data1
                    )
                }
                HStack(alignment: .firstTextBaseline, spacing: Mh.abstand3) {
                    Text(anzahlText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    zielText
                }
                .mhText(.small)
                .monospacedDigit()
                .foregroundStyle(Mh.textSecondary)
            }
            .padding(.vertical, Mh.abstand3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(standardText)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var zielText: some View {
        if stats.tageszielMl == 0 {
            Text("kein Tagesziel")
        } else if stats.zielErreicht {
            HStack(spacing: Mh.abstand1) {
                MhSymbol("MhCheck", groesse: Mh.symbolKlein)
                Text("Ziel erreicht")
            }
            .foregroundStyle(Mh.textGreen)
        } else {
            Text(verbatim: "\(stats.fortschrittPct ?? 0) % von \(stats.tageszielMl) ml")
        }
    }
}

/// Einträge eines Tages: Gruppenlabel mit Haarlinie, darunter Zeilen.
private struct TagesGruppe: View {
    let titel: String
    let eintraege: [TrinkEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(titel.uppercased())
                .mhText(.caption)
                .foregroundStyle(Mh.textTertiary)
                .padding(.bottom, Mh.abstand1)
                .accessibilityAddTraits(.isHeader)
            MhTrennlinie()
            ForEach(Array(eintraege.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { MhTrennlinie() }
                EntryRow(entry: entry)
            }
        }
    }
}

private struct NewEntryForm: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var drink = "Wasser"
    @State private var amount = "250"
    @State private var customTime: Date?
    @State private var busy = false
    @State private var showTimePicker = false

    private var menge: Int? { Int(amount.trimmingCharacters(in: .whitespaces)) }

    /// Segment „Jetzt | Andere Uhrzeit“: „Andere Uhrzeit“ öffnet die Zeitwahl.
    private var zeitWahl: Binding<Int> {
        Binding(
            get: { customTime == nil ? 0 : 1 },
            set: { index in
                if index == 0 {
                    customTime = nil
                } else {
                    showTimePicker = true
                }
            }
        )
    }

    var body: some View {
        let nebeneinander = !typeSize.isAccessibilitySize
        let felder = nebeneinander
            ? AnyLayout(HStackLayout(alignment: .top, spacing: Mh.abstand3))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: Mh.abstand4))

        VStack(alignment: .leading, spacing: 0) {
            Abschnittskopf("Neuer Eintrag")
            felder {
                TrinkTextField(label: "Getränk", text: $drink, placeholder: "z. B. Wasser, Apfelschorle", maxLength: 60)
                TrinkTextField(label: "Menge (ml)", text: $amount, placeholder: "z. B. 250", keyboard: .numberPad)
                    .frame(maxWidth: nebeneinander ? 128 : CGFloat.infinity)
            }

            VStack(alignment: .leading, spacing: Mh.abstand2) {
                FeldLabel("Klassische Größen")
                FlowLayout {
                    ForEach(vorwahlMengen, id: \.self) { value in
                        MhAuswahl("\(String(value)) ml", gewaehlt: menge == value) { amount = String(value) }
                    }
                }
            }
            .padding(.top, Mh.abstand5)

            VStack(alignment: .leading, spacing: Mh.abstand2) {
                FeldLabel("Uhrzeit")
                MhSegmente(optionen: ["Jetzt", "Andere Uhrzeit"], gewaehlt: zeitWahl)
                if let customTime {
                    HStack(alignment: .firstTextBaseline, spacing: Mh.abstand3) {
                        Text(verbatim: "Zeitpunkt: \(BerlinTime.formatDayMonth(customTime)) \(BerlinTime.formatTime(customTime))")
                            .mhText(.small)
                            .monospacedDigit()
                            .foregroundStyle(Mh.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Ändern") { showTimePicker = true }
                            .buttonStyle(.mhText)
                    }
                }
            }
            .padding(.top, Mh.abstand5)

            Button("Eintrag anlegen") { submit(asFavorite: false) }
                .buttonStyle(MhHauptButtonStil(breit: true))
                .disabled(busy)
                .padding(.top, Mh.abstand6)
            Button("Als Favorit speichern") { submit(asFavorite: true) }
                .buttonStyle(.mhText)
                .disabled(busy)
                .frame(maxWidth: .infinity)
                .padding(.top, Mh.abstand1)
        }
        .sheet(isPresented: $showTimePicker) {
            TimePickerSheet(initial: customTime ?? Date()) { picked in
                // Nur die Uhrzeit übernehmen; heute in Berlin, sonst gestern.
                let now = Date()
                let berlinNow = BerlinTime.components(now)
                let berlinPicked = BerlinTime.components(picked)
                var candidate = BerlinTime.berlinToUtc(
                    BerlinTime.utcDate(berlinNow.year!, berlinNow.month!, berlinNow.day!, berlinPicked.hour!, berlinPicked.minute!)
                )
                if candidate > now {
                    // Zeit in der Zukunft lehnt der Server ab — als gestern verbuchen.
                    candidate = candidate.addingTimeInterval(-86_400)
                }
                customTime = candidate
            }
        }
    }

    private func submit(asFavorite: Bool) {
        let getraenk = drink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !getraenk.isEmpty, let menge else {
            toasts.show("Getränk und Menge angeben.", isError: true)
            return
        }
        busy = true
        Task {
            let error = asFavorite
                ? await store.addFavorite(getraenk, menge)
                : await store.addEntry(getraenk, menge, createTime: customTime)
            busy = false
            if error == nil, !asFavorite { customTime = nil }
            toasts.result(error, success: asFavorite ? "Favorit „\(getraenk) \(menge) ml“ angelegt" : "\(getraenk) \(menge) ml eingetragen")
        }
    }
}

/// Eintragszeile (`.list-row`): Uhrzeit, Getränk, Menge, Löschen.
private struct EntryRow: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    let entry: TrinkEntry

    var body: some View {
        HStack(alignment: .center, spacing: Mh.abstand3) {
            Text(verbatim: BerlinTime.formatTime(entry.createdAt))
                .mhText(.small)
                .monospacedDigit()
                .foregroundStyle(Mh.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.getraenk)
                    .mhText(.body)
                    .foregroundStyle(Mh.textStrong)
                if entry.isPending {
                    HStack(spacing: Mh.abstand1) {
                        MhSymbol("MhClock", groesse: 14)
                        Text("wartet auf Übertragung")
                    }
                    .mhText(.small)
                    .foregroundStyle(Mh.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: "\(entry.mengeMl) ml")
                .mhText(.body)
                .monospacedDigit()
                .foregroundStyle(Mh.text)
                .lineLimit(1)
            MhSymbolButton("MhTrash", beschreibung: "Eintrag löschen", farbe: Mh.textTertiary) {
                Task {
                    if let error = await store.deleteEntry(entry.id) { toasts.show(error, isError: true) }
                }
            }
        }
        .padding(.vertical, Mh.abstand1)
        .frame(minHeight: 52)
    }
}
