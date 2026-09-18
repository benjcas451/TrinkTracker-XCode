import SwiftUI

// MARK: - Text-Abfrage (Nutzername, Tagesziel …)

struct TextPrompt: Identifiable {
    let id = UUID()
    let title: String
    let label: String
    var initial = ""
    var maxLength = 50
    var confirmLabel = "Speichern"
    var keyboard: UIKeyboardType = .default
    var secure = false
    let onConfirm: (String) -> Void
}

private struct TextPromptModifier: ViewModifier {
    @Binding var prompt: TextPrompt?
    @State private var text = ""

    func body(content: Content) -> some View {
        content.alert(
            prompt?.title ?? "",
            isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
            presenting: prompt
        ) { prompt in
            Group {
                if prompt.secure {
                    SecureField(prompt.label, text: $text)
                } else {
                    TextField(prompt.label, text: $text)
                        .keyboardType(prompt.keyboard)
                }
            }
            .onAppear { text = prompt.initial }
            Button("Abbrechen", role: .cancel) {}
            Button(prompt.confirmLabel) {
                let value = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(prompt.maxLength))
                if !value.isEmpty || prompt.secure { prompt.onConfirm(value) }
            }
        } message: { _ in
            EmptyView()
        }
    }
}

// MARK: - Bestätigung (Löschen, Backup einspielen)

struct ConfirmPrompt: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var confirmLabel = "Löschen"
    var destructive = true
    let onConfirm: () -> Void
}

private struct ConfirmPromptModifier: ViewModifier {
    @Binding var prompt: ConfirmPrompt?

    func body(content: Content) -> some View {
        content.alert(
            prompt?.title ?? "",
            isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
            presenting: prompt
        ) { prompt in
            Button("Abbrechen", role: .cancel) {}
            Button(prompt.confirmLabel, role: prompt.destructive ? .destructive : nil, action: prompt.onConfirm)
        } message: { prompt in
            Text(prompt.message)
        }
    }
}

extension View {
    func textPrompt(_ prompt: Binding<TextPrompt?>) -> some View {
        modifier(TextPromptModifier(prompt: prompt))
    }

    func confirmPrompt(_ prompt: Binding<ConfirmPrompt?>) -> some View {
        modifier(ConfirmPromptModifier(prompt: prompt))
    }
}

// MARK: - Wiederkehrende Dialoge

/// Baut die Dialoge, die Heute- und Einstellungs-Screen gemeinsam nutzen.
@MainActor
enum Dialogs {
    static func createUser(store: AppStore, toasts: ToastCenter) -> TextPrompt {
        TextPrompt(title: "Nutzer anlegen", label: "Name", confirmLabel: "Anlegen") { name in
            Task { toasts.result(await store.createUser(name), success: "Nutzer „\(name)“ angelegt") }
        }
    }

    static func renameUser(_ user: TrinkUser, store: AppStore, toasts: ToastCenter) -> TextPrompt {
        TextPrompt(title: "Nutzer umbenennen", label: "Name", initial: user.name) { name in
            Task { toasts.result(await store.renameUser(user.id, name), success: "Umbenannt in „\(name)“") }
        }
    }

    static func deleteUser(_ user: TrinkUser, store: AppStore, toasts: ToastCenter) -> ConfirmPrompt {
        ConfirmPrompt(title: "Nutzer löschen?", message: "„\(user.name)“ und alle zugehörigen Einträge werden gelöscht.") {
            Task { toasts.result(await store.deleteUser(user.id), success: "Nutzer gelöscht") }
        }
    }

    static func deleteFavorite(_ favorite: TrinkFavorite, store: AppStore, toasts: ToastCenter) -> ConfirmPrompt {
        ConfirmPrompt(title: "Favorit löschen?", message: "„\(favorite.getraenk) · \(favorite.mengeMl) ml“ entfernen.") {
            Task { toasts.result(await store.deleteFavorite(favorite.id), success: "Favorit gelöscht") }
        }
    }

    /// Tagesziel je Nutzer (0 schaltet es aus).
    static func tagesziel(_ user: TrinkUser, store: AppStore, toasts: ToastCenter) -> TextPrompt {
        TextPrompt(
            title: "Tagesziel für \(user.name)",
            label: "Tagesziel in ml (0 = aus)",
            initial: String(user.tageszielMl),
            maxLength: 5,
            keyboard: .numberPad
        ) { value in
            guard let ml = Int(value) else {
                toasts.show("Bitte eine Zahl eingeben.", isError: true)
                return
            }
            Task {
                toasts.result(await store.setTagesziel(user.id, ml), success: ml == 0 ? "Tagesziel ausgeschaltet" : "Tagesziel: \(ml) ml")
            }
        }
    }
}

// MARK: - Favorit anlegen: Getränk + Menge, Vorwahl-Chips inklusive.

struct CreateFavoriteSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var drink = ""
    @State private var amount = "250"
    @FocusState private var drinkFocused: Bool

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TrinkSpacing.md) {
                    TrinkTextField(label: "Getränk", text: $drink, maxLength: 60)
                        .focused($drinkFocused)
                    TrinkTextField(label: "Menge", text: $amount, suffix: "ml", keyboard: .numberPad)
                    FlowLayout {
                        ForEach(vorwahlMengen, id: \.self) { menge in
                            TrinkChip(label: String(menge), selected: Int(amount) == menge) { amount = String(menge) }
                        }
                    }
                }
                .padding(TrinkSpacing.lg)
            }
            .background(c.background)
            .navigationTitle("Favorit anlegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") { save() }
                }
            }
            .onAppear { drinkFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let getraenk = drink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !getraenk.isEmpty, let menge = Int(amount.trimmingCharacters(in: .whitespaces)) else {
            toasts.show("Getränk und Menge angeben.", isError: true)
            return
        }
        dismiss()
        Task { toasts.result(await store.addFavorite(getraenk, menge), success: "Favorit angelegt") }
    }
}

// MARK: - Uhrzeit für einen Eintrag

struct TimePickerSheet: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Date
    let onPick: (Date) -> Void

    init(initial: Date, onPick: @escaping (Date) -> Void) {
        _selection = State(initialValue: initial)
        self.onPick = onPick
    }

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        NavigationStack {
            VStack {
                DatePicker("Uhrzeit des Eintrags", selection: $selection, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.timeZone, TimeZone(identifier: "Europe/Berlin") ?? .current)
                Text("Zeiten in Europe/Berlin. Liegt die Uhrzeit in der Zukunft, wird der Eintrag auf gestern gebucht.")
                    .trinkText(.bodySmall)
                    .foregroundStyle(c.textSecondary)
                    .padding(.horizontal, TrinkSpacing.lg)
                Spacer()
            }
            .background(c.background)
            .navigationTitle("Uhrzeit des Eintrags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        onPick(selection)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
