import SwiftUI

/// Unterseite „Nutzer“ (wie `nutzer.php`/`favoriten.php` im Web): Nutzer und
/// Tagesziele, Standardnutzer dieses Geräts, Favoriten des gewählten Nutzers.
/// Anlegen, Umbenennen und Löschen gibt es nur, wenn der Modus es anbietet
/// (lokal immer, Server nur mit den erweiterten Server-Actions); sonst steht
/// dort, warum nicht.
struct NutzerView: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts

    @State private var textPrompt: TextPrompt?
    @State private var confirmPrompt: ConfirmPrompt?

    var body: some View {
        let canManage = store.supportsUserManagement
        Unterseitenrahmen("Nutzer") {
            if !canManage {
                Hinweistext("In diesem Modus bietet die API kein Anlegen, Umbenennen oder Löschen von Nutzern. Das übernimmt die Web-App, oder du schaltest in den Einstellungen die erweiterten Server-Actions ein.")
                    .padding(.bottom, Mh.abstand4)
            }

            Abschnittskopf("Nutzer und Tagesziele")
            if store.users.isEmpty {
                MhLeer("Noch keine Nutzer.")
            } else {
                ForEach(Array(store.users.enumerated()), id: \.element.id) { index, user in
                    if index > 0 { MhTrennlinie() }
                    nutzerZeile(user, canManage: canManage)
                }
                Hinweistext("Mit dem Stern legst du den Standardnutzer fest: Mit ihm startet die App auf diesem Gerät. Praktisch, wenn jedes Familienmitglied sein eigenes Telefon hat. Für andere eintragen geht weiterhin per Tipp auf den Namen.")
                    .padding(.top, Mh.abstand3)
            }

            if let user = store.selectedUser {
                favoriten(of: user, canManage: canManage).padding(.top, Mh.abstand8)
            }
        } hauptaktion: {
            if canManage {
                Button("Nutzer anlegen") { textPrompt = Dialogs.createUser(store: store, toasts: toasts) }
                    .buttonStyle(MhHauptButtonStil(klein: true))
            }
        }
        .textPrompt($textPrompt)
        .confirmPrompt($confirmPrompt)
    }

    private func nutzerZeile(_ user: TrinkUser, canManage: Bool) -> some View {
        let isDefault = store.isDefaultUser(user)
        let meta = [
            user.tageszielMl == 0 ? "kein Tagesziel" : "Tagesziel \(user.tageszielMl) ml",
            isDefault ? "Standard auf diesem Gerät" : nil,
        ].compactMap { $0 }.joined(separator: " · ")

        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.custom(MhSchrift.medium, size: 16, relativeTo: .body))
                    .foregroundStyle(Mh.textStrong)
                Text(verbatim: meta)
                    .mhText(.small)
                    .monospacedDigit()
                    .foregroundStyle(Mh.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            MhSymbolButton(
                isDefault ? "MhStarGefuellt" : "MhStar",
                beschreibung: isDefault ? "Standardnutzer entfernen" : "Als Standardnutzer festlegen",
                farbe: isDefault ? Mh.textYellow : Mh.textSecondary
            ) {
                Task {
                    await store.setDefaultUser(isDefault ? nil : user)
                    toasts.show(isDefault
                                ? "Kein Standardnutzer mehr. Die App merkt sich die letzte Auswahl."
                                : "\(user.name) ist jetzt Standard auf diesem Gerät.")
                }
            }
            Menu {
                Button("Tagesziel ändern") { textPrompt = Dialogs.tagesziel(user, store: store, toasts: toasts) }
                if canManage {
                    Button("Umbenennen") { textPrompt = Dialogs.renameUser(user, store: store, toasts: toasts) }
                    Button("Löschen", role: .destructive) {
                        confirmPrompt = Dialogs.deleteUser(user, store: store, toasts: toasts)
                    }
                }
            } label: {
                MhSymbol("MhMore")
                    .frame(width: Mh.touch, height: Mh.touch)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(Mh.textSecondary)
            .accessibilityLabel(Text(verbatim: "Aktionen für \(user.name)"))
        }
        .padding(.vertical, Mh.abstand2)
        .frame(minHeight: 52)
    }

    @ViewBuilder
    private func favoriten(of user: TrinkUser, canManage: Bool) -> some View {
        Abschnittskopf("Favoriten von \(user.name)")
        if !canManage {
            Hinweistext("Favoriten löschen bietet die API in diesem Modus nur mit den erweiterten Server-Actions (Einstellungen).")
                .padding(.bottom, Mh.abstand3)
        }
        if store.favorites.isEmpty {
            MhLeer("Noch keine Favoriten. In der Ansicht Heute über „Hinzufügen“ oder „Als Favorit speichern“ anlegen.")
        } else {
            ForEach(Array(store.favorites.enumerated()), id: \.element.id) { index, favorite in
                if index > 0 { MhTrennlinie() }
                HStack(spacing: Mh.abstand3) {
                    Text(favorite.getraenk)
                        .mhText(.body)
                        .foregroundStyle(Mh.textStrong)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: "\(favorite.mengeMl) ml")
                        .mhText(.body)
                        .monospacedDigit()
                        .foregroundStyle(Mh.text)
                    if canManage {
                        MhSymbolButton("MhTrash", beschreibung: "Favorit löschen", farbe: Mh.textTertiary) {
                            confirmPrompt = Dialogs.deleteFavorite(favorite, store: store, toasts: toasts)
                        }
                    }
                }
                .frame(minHeight: 52)
            }
            if canManage {
                Hinweistext("Andere Nutzer in der Ansicht Heute auswählen, um deren Favoriten zu bearbeiten.")
                    .padding(.top, Mh.abstand3)
            }
        }
    }
}
