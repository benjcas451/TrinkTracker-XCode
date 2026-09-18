import SwiftUI
import UIKit

/// Screen 1 „Heute" (Spec 5): Familienübersicht, Nutzerwahl,
/// Favoriten-Schnellwahl, neuer Eintrag, Liste heute & gestern.
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.colorScheme) private var scheme

    @State private var textPrompt: TextPrompt?
    @State private var confirmPrompt: ConfirmPrompt?
    @State private var showCreateFavorite = false

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Heute").trinkText(.headlineMedium).foregroundStyle(c.textStrong)
                    Spacer()
                    if store.loading { ProgressView().controlSize(.small) }
                }
                .padding(.bottom, TrinkSpacing.lg)

                OfflineBanner(isOffline: store.isOffline, pendingCount: store.pendingCount) {
                    Task { await store.flushQueue() }
                }

                if let error = store.errorMessage {
                    ErrorBox(message: error).padding(.bottom, TrinkSpacing.lg)
                }

                if store.users.isEmpty {
                    if store.supportsUserManagement {
                        EmptyHint(
                            title: "Lege zuerst Nutzer an",
                            description: "Die App startet ohne vorgegebene Nutzer, Ziele oder Favoriten. Lege für jedes Familienmitglied einen Nutzer an."
                        ) {
                            Button("Nutzer anlegen") { textPrompt = Dialogs.createUser(store: store, toasts: toasts) }
                                .buttonStyle(.trinkFilled)
                        }
                    } else {
                        EmptyHint(
                            title: "Lege zuerst Nutzer an",
                            description: "In diesem Modus legt die Web-App die Nutzer an. Prüfe die Verbindung in den Einstellungen."
                        )
                    }
                } else {
                    SectionTitle("Familie")
                    ForEach(store.users) { user in
                        UserTile(
                            user: user,
                            stats: store.todayByUser[user.id] ?? .empty,
                            selected: user.id == store.selectedUserId,
                            isDefault: store.isDefaultUser(user)
                        ) {
                            Task { await store.selectUser(user.id) }
                        }
                        .padding(.bottom, TrinkSpacing.md)
                    }
                    userChips.padding(.top, TrinkSpacing.sm)
                    favorites.padding(.top, TrinkSpacing.xl)
                    NewEntryForm().padding(.top, TrinkSpacing.xl)
                    entryList.padding(.top, TrinkSpacing.xl)
                }

                Text("Zeiten in Europe/Berlin — dieselben Tagesgrenzen wie der Server.")
                    .trinkText(.bodySmall)
                    .foregroundStyle(c.textSecondary)
                    .padding(.top, TrinkSpacing.xxl)
            }
            .padding(TrinkSpacing.lg)
        }
        .background(c.background)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await store.refresh() }
        .textPrompt($textPrompt)
        .confirmPrompt($confirmPrompt)
        .sheet(isPresented: $showCreateFavorite) { CreateFavoriteSheet() }
    }

    private var userChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TrinkSpacing.sm) {
                ForEach(store.users) { user in
                    TrinkChip(label: user.name, selected: user.id == store.selectedUserId) {
                        Task { await store.selectUser(user.id) }
                    }
                }
            }
        }
    }

    private var favorites: some View {
        let c = TrinkPalette.resolve(scheme)
        return VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Favoriten") {
                Button("Hinzufügen") { showCreateFavorite = true }
                    .buttonStyle(.trinkText)
            }
            if store.favorites.isEmpty {
                Text("Noch keine Favoriten — ein Tipp auf „Hinzufügen“ legt eine Schnellwahl an.")
                    .trinkText(.bodySmall)
                    .foregroundStyle(c.textSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TrinkSpacing.sm) {
                        ForEach(store.favorites) { favorite in
                            TrinkChip(
                                label: "\(favorite.getraenk) · \(favorite.mengeMl) ml",
                                tone: .favorite,
                                action: { tapFavorite(favorite) }
                            )
                            // Gedrückt halten öffnet das Menü — sichtbarer als ein stiller Long-Press.
                            .contextMenu {
                                Button {
                                    tapFavorite(favorite)
                                } label: {
                                    Label("Jetzt eintragen", systemImage: "plus.circle")
                                }
                                if store.supportsUserManagement {
                                    Button(role: .destructive) {
                                        confirmPrompt = Dialogs.deleteFavorite(favorite, store: store, toasts: toasts)
                                    } label: {
                                        Label("Favorit löschen", systemImage: "trash")
                                    }
                                } else {
                                    Text("Löschen nur mit erweiterten Server-Actions (Einstellungen)")
                                }
                            }
                        }
                    }
                }
                Text(store.supportsUserManagement
                     ? "Tippen trägt ein · gedrückt halten zum Löschen. Alle Favoriten stehen auch in den Einstellungen."
                     : "Tippen trägt ein. Löschen bietet die API in diesem Modus nur mit den erweiterten Server-Actions.")
                    .trinkText(.bodySmall)
                    .foregroundStyle(c.textSecondary)
                    .padding(.top, TrinkSpacing.sm)
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

    private var entryList: some View {
        let c = TrinkPalette.resolve(scheme)
        let now = Date()
        let todayKey = BerlinTime.dateKey(now)
        let yesterdayKey = BerlinTime.dateKey(now.addingTimeInterval(-86_400))
        // Heute & gestern (Spec 4) — ältere Einträge zeigt die Statistik.
        let visible = store.entries.filter {
            let key = BerlinTime.dateKey($0.createdAt)
            return key == todayKey || key == yesterdayKey
        }

        return VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Heute & gestern") {
                Button("Rückgängig") {
                    Task { toasts.result(await store.undoLast(), success: "Letzter Eintrag entfernt") }
                }
                .buttonStyle(.trinkText)
                .disabled(visible.isEmpty)
            }
            if visible.isEmpty {
                Text("Für heute und gestern ist noch nichts erfasst.")
                    .trinkText(.bodySmall)
                    .foregroundStyle(c.textSecondary)
            } else {
                ForEach(visible) { entry in
                    EntryRow(entry: entry, isToday: BerlinTime.dateKey(entry.createdAt) == todayKey)
                        .padding(.bottom, TrinkSpacing.sm)
                }
            }
        }
    }
}

private struct UserTile: View {
    @Environment(\.colorScheme) private var scheme
    let user: TrinkUser
    let stats: TodayStats
    let selected: Bool
    let isDefault: Bool
    let onTap: () -> Void

    private var subtitle: String {
        if stats.tageszielMl == 0 { return "\(stats.anzahl) Einträge · kein Tagesziel" }
        if stats.zielErreicht { return "\(stats.anzahl) Einträge · Ziel erreicht (\(stats.tageszielMl) ml)" }
        return "\(stats.anzahl) Einträge · \(stats.fortschrittPct ?? 0) % von \(stats.tageszielMl) ml"
    }

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        TrinkCard(color: selected ? (c.isDark ? c.subtle : c.successBg) : c.surface, onTap: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: TrinkSpacing.sm) {
                    Text(user.name).trinkText(.titleMedium)
                    if isDefault {
                        Image(systemName: "star.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(c.isDark ? c.yellow300 : c.yellow900)
                            .accessibilityLabel("Standardnutzer dieses Geräts")
                    }
                    Spacer()
                    Text(verbatim: "\(stats.ml) ml")
                        .trinkText(.titleLarge, tabular: true)
                        .foregroundStyle(c.accentText)
                }
                GoalProgressBar(stats: stats).padding(.top, TrinkSpacing.md)
                Text(subtitle)
                    .trinkText(.bodySmall)
                    .foregroundStyle(c.textSecondary)
                    .padding(.top, TrinkSpacing.sm)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct NewEntryForm: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.colorScheme) private var scheme

    @State private var drink = "Wasser"
    @State private var amount = "250"
    @State private var customTime: Date?
    @State private var busy = false
    @State private var showTimePicker = false

    private var menge: Int? { Int(amount.trimmingCharacters(in: .whitespaces)) }

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Neuer Eintrag")
            TrinkCard {
                VStack(alignment: .leading, spacing: TrinkSpacing.md) {
                    TrinkTextField(label: "Getränk", text: $drink, maxLength: 60)
                    TrinkTextField(label: "Menge", text: $amount, suffix: "ml", keyboard: .numberPad)
                    FlowLayout {
                        ForEach(vorwahlMengen, id: \.self) { value in
                            TrinkChip(label: String(value), selected: menge == value) { amount = String(value) }
                        }
                    }
                    HStack {
                        Text(customTime.map { "Zeitpunkt: \(BerlinTime.formatDayMonth($0)) \(BerlinTime.formatTime($0))" } ?? "Zeitpunkt: jetzt")
                            .trinkText(.bodySmall)
                            .foregroundStyle(c.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if customTime == nil {
                            Button("Andere Uhrzeit") { showTimePicker = true }.buttonStyle(.trinkText)
                        } else {
                            Button("Jetzt") { customTime = nil }.buttonStyle(.trinkText)
                        }
                    }
                    .padding(.top, TrinkSpacing.xs)
                    HStack(spacing: TrinkSpacing.md) {
                        Button("Eintragen") { submit(asFavorite: false) }
                            .buttonStyle(.trinkFilled)
                            .frame(maxWidth: .infinity)
                            .disabled(busy)
                        Button("Als Favorit") { submit(asFavorite: true) }
                            .buttonStyle(.trinkOutlined)
                            .disabled(busy)
                    }
                }
            }
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

private struct EntryRow: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.colorScheme) private var scheme
    let entry: TrinkEntry
    let isToday: Bool

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        var parts = [isToday ? "heute" : "gestern", BerlinTime.formatTime(entry.createdAt)]
        if entry.isPending { parts.append("wartet auf Übertragung") }

        return TrinkCard(padding: .symmetric(horizontal: TrinkSpacing.lg, vertical: TrinkSpacing.sm)) {
            HStack(spacing: TrinkSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.getraenk).trinkText(.bodyLarge)
                    Text(parts.joined(separator: " · "))
                        .trinkText(.bodySmall)
                        .foregroundStyle(c.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: "\(entry.mengeMl) ml")
                    .trinkText(.titleMedium, tabular: true)
                    .foregroundStyle(c.accentText)
                Button {
                    Task {
                        if let error = await store.deleteEntry(entry.id) { toasts.show(error, isError: true) }
                    }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(c.danger)
                        .frame(width: TrinkSpacing.minTouch, height: TrinkSpacing.minTouch)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Löschen")
            }
        }
    }
}
