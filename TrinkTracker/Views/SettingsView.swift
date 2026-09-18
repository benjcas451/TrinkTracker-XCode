import SwiftUI
import UniformTypeIdentifiers

/// Screen 3 „Einstellungen" (Spec 5). Die Verbindung steht oben; jede Familie
/// trägt Host und Key selbst ein — nichts ist vorausgefüllt.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Einstellungen")
                    .trinkText(.headlineMedium)
                    .foregroundStyle(c.textStrong)
                    .padding(.bottom, TrinkSpacing.lg)
                ConnectionSection()
                UserSection().padding(.top, TrinkSpacing.xl)
                if settings.mode == .demo {
                    BackupSection().padding(.top, TrinkSpacing.xl)
                }
                InfoSection().padding(.top, TrinkSpacing.xl)
            }
            .padding(TrinkSpacing.lg)
            .padding(.bottom, TrinkSpacing.xxl)
        }
        .background(c.background)
        .scrollDismissesKeyboard(.interactively)
        // Änderungen an Modus, URLs oder Keys bauen den Dienst neu — ohne Neustart.
        .onChange(of: settings.revision) { _, _ in store.settingsChanged() }
    }
}

// MARK: - Verbindung

private struct RadioRow: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        Button(action: action) {
            HStack(spacing: TrinkSpacing.md) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? c.green600 : c.textSecondary)
                Text(label).trinkText(.bodyLarge).foregroundStyle(c.text)
                Spacer()
            }
            .frame(minHeight: TrinkSpacing.minTouch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ConnectionSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        let mode = settings.mode
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Verbindung")
            TrinkCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ConnectionKind.allCases) { kind in
                        RadioRow(label: kind.label, selected: mode.kind == kind) {
                            if kind != mode.kind {
                                settings.setMode(kind == .local ? .demo : ConnectionMode.defaultAuthMode)
                            }
                        }
                    }

                    if mode.isServer {
                        Divider().padding(.vertical, TrinkSpacing.md)
                        Text("Authentifizierung")
                            .trinkText(.labelMedium)
                            .foregroundStyle(c.textSecondary)
                        ForEach(ConnectionMode.authModes) { option in
                            RadioRow(label: option.authLabel, selected: mode == option) { settings.setMode(option) }
                        }
                        Divider().padding(.vertical, TrinkSpacing.md)

                        BaseUrlField(mode: mode)

                        SecretField(
                            label: mode == .apiKey ? "API-Key" : "API-Key (optional)",
                            helper: mode == .apiKey
                                ? "Wird als X-API-Key gesendet."
                                : "Leer lassen, wenn der Mandant keinen Key erwartet — dann wird kein X-API-Key-Header gesendet.",
                            value: settings.apiKey(for: mode),
                            onSave: { settings.setApiKey(mode, $0) }
                        )
                        .padding(.top, TrinkSpacing.md)

                        if mode == .cloudflare {
                            SecretField(
                                label: "CF-Access-Client-Id",
                                helper: "Service Token der Access-Anwendung dieses Hosts (endet üblich auf .access).",
                                value: settings.cfAccessClientId,
                                onSave: { settings.setCfAccessClientId($0) }
                            )
                            .padding(.top, TrinkSpacing.md)
                            SecretField(
                                label: "CF-Access-Client-Secret",
                                value: settings.cfAccessClientSecret,
                                onSave: { settings.setCfAccessClientSecret($0) }
                            )
                            .padding(.top, TrinkSpacing.md)
                        }

                        if mode == .api {
                            CertSection().padding(.top, TrinkSpacing.md)
                        }

                        ConnectionTest().padding(.top, TrinkSpacing.lg)

                        Divider().padding(.vertical, TrinkSpacing.md)
                        Toggle(isOn: Binding(
                            get: { settings.serverUserManagement },
                            set: { settings.setServerUserManagement($0) }
                        )) {
                            VStack(alignment: .leading, spacing: TrinkSpacing.xs) {
                                Text("Erweiterte Server-Actions").trinkText(.bodyLarge)
                                Text("Nutzer- und Favoritenverwaltung über die API. Nur einschalten, wenn der Mandant nutzer_anlegen, nutzer_umbenennen, nutzer_loeschen und favorit_loeschen installiert hat.")
                                    .trinkText(.bodySmall)
                                    .foregroundStyle(c.textSecondary)
                            }
                        }
                        .tint(c.green600)
                    }
                }
            }
        }
    }
}

/// Basis-URL als Pflegefeld: initial leer, nur ein Formathinweis als
/// Platzhalter, Speichern ohne Neustart (Spec 3.2).
private struct BaseUrlField: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.colorScheme) private var scheme
    let mode: ConnectionMode

    @State private var text = ""
    @State private var error: String?

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        VStack(alignment: .leading, spacing: TrinkSpacing.xs) {
            HStack(alignment: .bottom, spacing: TrinkSpacing.sm) {
                // Ohne Modus im Text: Die gewählte Authentifizierung steht in
                // derselben Karte direkt darüber.
                TrinkTextField(label: "Basis-URL", text: $text, placeholder: baseUrlPlaceholder, keyboard: .URL, error: error, onSubmit: save)
                Button(action: save) {
                    Image(systemName: "checkmark")
                        .frame(width: TrinkSpacing.minTouch, height: TrinkSpacing.minTouch)
                }
                .buttonStyle(.trinkOutlined)
                .accessibilityLabel("Speichern")
                .padding(.bottom, error == nil ? 0 : 22)
            }
            Text("Eigenes Feld je Modus — ein Wechsel überschreibt nichts. Die Änderung wirkt sofort, die Warteschlange wechselt mit.")
                .trinkText(.bodySmall)
                .foregroundStyle(c.textSecondary)
        }
        .onAppear { text = settings.baseUrl(for: mode) }
        .onChange(of: mode) { _, newMode in
            text = settings.baseUrl(for: newMode)
            error = nil
        }
    }

    private func save() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let problem = value.isEmpty ? nil : validateBaseUrl(value)
        error = problem
        if problem != nil { return }
        settings.setBaseUrl(mode, value)
        toasts.show(value.isEmpty ? "Basis-URL geleert" : "Basis-URL gespeichert")
    }
}

private struct SecretField: View {
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.colorScheme) private var scheme
    let label: String
    var helper: String?
    let value: String
    let onSave: (String) -> Void

    @State private var text = ""

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        VStack(alignment: .leading, spacing: TrinkSpacing.xs) {
            HStack(alignment: .bottom, spacing: TrinkSpacing.sm) {
                TrinkTextField(label: label, text: $text, secure: true, onSubmit: save)
                Button(action: save) {
                    Image(systemName: "checkmark")
                        .frame(width: TrinkSpacing.minTouch, height: TrinkSpacing.minTouch)
                }
                .buttonStyle(.trinkOutlined)
                .accessibilityLabel("Speichern")
            }
            if let helper {
                Text(helper).trinkText(.bodySmall).foregroundStyle(c.textSecondary)
            }
        }
        .onAppear { text = value }
        // Je Modus ein eigener Slot: beim Wechsel den Feldinhalt nachziehen,
        // damit ein Key nie im Feld eines anderen Modus landet.
        .onChange(of: label) { _, _ in text = value }
        .onChange(of: value) { _, newValue in text = newValue }
    }

    private func save() {
        onSave(text)
        toasts.show("\(label) gespeichert")
    }
}

/// Client-Zertifikat für mTLS: p12 oder PEM-Paar in den App-Ordner übernehmen.
private struct CertSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.colorScheme) private var scheme

    @State private var status = "Zertifikatsstatus wird geprüft …"
    @State private var importing: ClientCertificateStore.FileKind?
    @State private var pendingP12: Data?
    @State private var passwordPrompt: TextPrompt?

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        VStack(alignment: .leading, spacing: TrinkSpacing.xs) {
            Text("Client-Zertifikat (mTLS)").trinkText(.labelLarge)
            Text(status).trinkText(.bodySmall).foregroundStyle(c.textSecondary)
            FlowLayout {
                Button("client.p12 wählen") { importing = .p12 }.buttonStyle(.trinkOutlined)
                Button("client.crt wählen") { importing = .cert }.buttonStyle(.trinkOutlined)
                Button("client.key wählen") { importing = .key }.buttonStyle(.trinkOutlined)
            }
            .padding(.top, TrinkSpacing.sm)
            Text("Empfohlen ist eine PKCS#12-Datei (client.p12). Alternativ PEM-Dateien; der Schlüssel muss dann ohne Passwort vorliegen. Die Dateien werden in den App-Ordner kopiert und liegen nicht im Backup der Einstellungen.")
                .trinkText(.bodySmall)
                .foregroundStyle(c.textSecondary)
        }
        .onAppear(perform: check)
        .fileImporter(
            isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }),
            allowedContentTypes: [.data, .item],
            allowsMultipleSelection: false
        ) { result in
            guard let kind = importing else { return }
            importing = nil
            handle(result, kind: kind)
        }
        .textPrompt($passwordPrompt)
    }

    private func check() {
        let s = ClientCertificateStore(folderPath: settings.certFolder).status()
        if s.p12 {
            status = "client.p12 gefunden in \(s.path)"
        } else if s.cert && s.key {
            status = "client.crt und client.key gefunden in \(s.path)"
        } else {
            var missing: [String] = []
            if !s.cert { missing.append("client.crt") }
            if !s.key { missing.append("client.key") }
            status = "Fehlt: \(missing.joined(separator: " und ")) — oder client.p12 (gesucht in \(s.path))"
        }
    }

    private func handle(_ result: Result<[URL], Error>, kind: ClientCertificateStore.FileKind) {
        switch result {
        case .failure(let error):
            toasts.show("Auswahl fehlgeschlagen: \(error.localizedDescription)", isError: true)
        case .success(let urls):
            guard let url = urls.first, let data = readSecurityScoped(url) else {
                toasts.show("Datei konnte nicht gelesen werden.", isError: true)
                return
            }
            if kind == .p12 {
                pendingP12 = data
                passwordPrompt = TextPrompt(title: "Passwort der p12-Datei", label: "Passwort", confirmLabel: "Importieren", secure: true) { password in
                    finishImport(data, kind: .p12, password: password)
                }
            } else {
                finishImport(data, kind: kind, password: nil)
            }
        }
    }

    private func finishImport(_ data: Data, kind: ClientCertificateStore.FileKind, password: String?) {
        do {
            let folder = try ClientCertificateStore.importBytes(data, kind: kind, p12Password: password)
            settings.setCertFolder(folder)
            toasts.show("Zertifikatsdatei übernommen")
        } catch {
            toasts.show(errorText(error), isError: true)
        }
        check()
    }
}

func readSecurityScoped(_ url: URL) -> Data? {
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    return try? Data(contentsOf: url)
}

/// „Verbindung testen" ruft `?action=users` und meldet die Anzahl Nutzer —
/// oder den Fehler samt CF-/Auth-Diagnose (Spec 3.2/3.3).
private struct ConnectionTest: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme

    @State private var busy = false
    @State private var result: String?
    @State private var failed = false

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        VStack(alignment: .leading, spacing: TrinkSpacing.sm) {
            Button(busy ? "Teste …" : "Verbindung testen") { Task { await test() } }
                .buttonStyle(.trinkFilled)
                .disabled(busy)
            if let result {
                Text(result)
                    .trinkText(.bodySmall)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(TrinkSpacing.md)
                    .background(failed ? c.errorBg : c.successBg)
                    .clipShape(RoundedRectangle(cornerRadius: TrinkRadii.sm, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: TrinkRadii.sm, style: .continuous).stroke(c.border, lineWidth: 1.5))
                    .textSelection(.enabled)
            }
        }
    }

    private func test() async {
        busy = true
        result = nil
        // Bewusst ohne Offline-Wrapper: der Test soll den echten Fehler zeigen.
        let service = createConfiguredEntryService(settings, offlineFaehig: false)
        do {
            let count = try await service.testConnection()
            result = "Verbindung ok — \(count) Nutzer gefunden."
            failed = false
        } catch {
            result = errorText(error)
            failed = true
        }
        await service.dispose()
        busy = false
    }
}

// MARK: - Nutzer & Favoriten

private struct UserSection: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.colorScheme) private var scheme

    @State private var textPrompt: TextPrompt?
    @State private var confirmPrompt: ConfirmPrompt?

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        let canManage = store.supportsUserManagement
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Nutzer & Tagesziele") {
                if canManage {
                    Button("Nutzer anlegen") { textPrompt = Dialogs.createUser(store: store, toasts: toasts) }
                        .buttonStyle(.trinkText)
                }
            }
            if !canManage {
                Text("In diesem Modus bietet die API kein Anlegen, Umbenennen oder Löschen von Nutzern. Das übernimmt die Web-App — oder du schaltest oben die erweiterten Server-Actions ein.")
                    .trinkText(.bodySmall)
                    .foregroundStyle(c.textSecondary)
                    .padding(.bottom, TrinkSpacing.md)
            }
            if store.users.isEmpty {
                Text("Noch keine Nutzer.").trinkText(.bodySmall).foregroundStyle(c.textSecondary)
            } else {
                ForEach(store.users) { user in
                    let isDefault = store.isDefaultUser(user)
                    TrinkCard(padding: .symmetric(horizontal: TrinkSpacing.lg, vertical: TrinkSpacing.sm)) {
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.name).trinkText(.bodyLarge)
                                Text(verbatim: [
                                    user.tageszielMl == 0 ? "kein Tagesziel" : "Tagesziel \(user.tageszielMl) ml",
                                    isDefault ? "Standard auf diesem Gerät" : nil,
                                ].compactMap { $0 }.joined(separator: " · "))
                                    .trinkText(.bodySmall)
                                    .foregroundStyle(c.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            iconButton(isDefault ? "star.fill" : "star",
                                       label: isDefault ? "Standardnutzer entfernen" : "Als Standardnutzer festlegen",
                                       color: isDefault ? (c.isDark ? c.yellow300 : c.yellow900) : c.text) {
                                Task {
                                    await store.setDefaultUser(isDefault ? nil : user)
                                    toasts.show(isDefault
                                                ? "Kein Standardnutzer mehr — die App merkt sich die letzte Auswahl."
                                                : "\(user.name) ist jetzt Standard auf diesem Gerät.")
                                }
                            }
                            iconButton("flag", label: "Tagesziel", color: c.text) {
                                textPrompt = Dialogs.tagesziel(user, store: store, toasts: toasts)
                            }
                            if canManage {
                                iconButton("pencil", label: "Umbenennen", color: c.text) {
                                    textPrompt = Dialogs.renameUser(user, store: store, toasts: toasts)
                                }
                                iconButton("trash", label: "Löschen", color: c.danger) {
                                    confirmPrompt = Dialogs.deleteUser(user, store: store, toasts: toasts)
                                }
                            }
                        }
                    }
                    .padding(.bottom, TrinkSpacing.sm)
                }
            }

            if !store.users.isEmpty {
                Text("★ Standardnutzer: Mit ihm startet die App auf diesem Gerät — praktisch, wenn jedes Familienmitglied sein eigenes Telefon hat. Zwischendurch für andere eintragen geht weiterhin per Tipp auf die Kachel.")
                    .trinkText(.bodySmall)
                    .foregroundStyle(c.textSecondary)
                    .padding(.top, TrinkSpacing.xs)
            }

            if let user = store.selectedUser {
                SectionTitle("Favoriten von \(user.name)").padding(.top, TrinkSpacing.lg)
                if !canManage {
                    Text("Favoriten löschen bietet die API in diesem Modus nur mit den erweiterten Server-Actions (oben).")
                        .trinkText(.bodySmall)
                        .foregroundStyle(c.textSecondary)
                        .padding(.bottom, TrinkSpacing.md)
                }
                if store.favorites.isEmpty {
                    Text("Noch keine Favoriten — im Heute-Screen über „Hinzufügen“ oder „Als Favorit“ anlegen.")
                        .trinkText(.bodySmall)
                        .foregroundStyle(c.textSecondary)
                } else {
                    ForEach(store.favorites) { favorite in
                        TrinkCard(padding: .symmetric(horizontal: TrinkSpacing.lg, vertical: TrinkSpacing.sm)) {
                            HStack {
                                Text(verbatim: "\(favorite.getraenk) · \(favorite.mengeMl) ml")
                                    .trinkText(.bodyLarge)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if canManage {
                                    iconButton("trash", label: "Löschen", color: c.danger) {
                                        confirmPrompt = Dialogs.deleteFavorite(favorite, store: store, toasts: toasts)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, TrinkSpacing.sm)
                    }
                    if canManage {
                        Text("Andere Nutzer oben in der Familie auswählen, um deren Favoriten zu bearbeiten.")
                            .trinkText(.bodySmall)
                            .foregroundStyle(c.textSecondary)
                    }
                }
            }
        }
        .textPrompt($textPrompt)
        .confirmPrompt($confirmPrompt)
    }

    private func iconButton(_ symbol: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: TrinkSpacing.minTouch, height: TrinkSpacing.minTouch)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Backup/Export

/// JSON-Datei für „In Dateien sichern".
struct JSONBackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct BackupSection: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.colorScheme) private var scheme

    @State private var busy = false
    @State private var exportDocument: JSONBackupDocument?
    @State private var showImporter = false
    @State private var pendingImport: [String: Any]?
    @State private var confirmPrompt: ConfirmPrompt?

    private var exportName: String {
        "trinktracker-backup-\(String(iso8601String(Date()).prefix(10))).json"
    }

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Backup & Export (lokaler Modus)")
            TrinkCard {
                VStack(alignment: .leading, spacing: TrinkSpacing.md) {
                    Text("Alle lokalen Daten als JSON sichern oder zurückspielen — auch für den Wechsel zwischen Geräten. Das Format ist zur Flutter-Version kompatibel.")
                        .trinkText(.bodySmall)
                        .foregroundStyle(c.textSecondary)
                    FlowLayout {
                        Button("Exportieren") { Task { await export() } }
                            .buttonStyle(.trinkFilled)
                            .disabled(busy)
                        Button("Importieren") { showImporter = true }
                            .buttonStyle(.trinkOutlined)
                            .disabled(busy)
                    }
                }
            }
        }
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportName
        ) { result in
            switch result {
            case .success: toasts.show("Backup gespeichert")
            case .failure(let error): toasts.show("Export fehlgeschlagen: \(error.localizedDescription)", isError: true)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .data], allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .confirmPrompt($confirmPrompt)
    }

    private func export() async {
        guard let local = store.localService else { return }
        busy = true
        defer { busy = false }
        do {
            let data = try await local.exportAll()
            let json = try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
            exportDocument = JSONBackupDocument(data: json)
        } catch {
            toasts.show("Export fehlgeschlagen: \(errorText(error))", isError: true)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            toasts.show("Auswahl fehlgeschlagen: \(error.localizedDescription)", isError: true)
        case .success(let urls):
            guard let url = urls.first, let data = readSecurityScoped(url),
                  let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                toasts.show("Import fehlgeschlagen: Kein JSON-Objekt.", isError: true)
                return
            }
            pendingImport = decoded
            confirmPrompt = ConfirmPrompt(
                title: "Backup einspielen?",
                message: "Der lokale Bestand wird vollständig durch das Backup ersetzt.",
                confirmLabel: "Einspielen",
                destructive: false
            ) {
                Task { await runImport() }
            }
        }
    }

    private func runImport() async {
        guard let local = store.localService, let data = pendingImport else { return }
        pendingImport = nil
        busy = true
        defer { busy = false }
        do {
            try await local.importAll(data)
            await store.refresh()
            toasts.show("Backup eingespielt")
        } catch {
            toasts.show("Import fehlgeschlagen: \(errorText(error))", isError: true)
        }
    }
}

// MARK: - Info

private struct InfoSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Info")
            TrinkCard(color: c.subtle) {
                VStack(alignment: .leading, spacing: TrinkSpacing.xs) {
                    InfoRow(label: "Modus", value: settings.mode.label)
                    InfoRow(
                        label: "Warteschlange",
                        value: settings.mode.isServer ? "\(store.pendingCount) ausstehend (\(settings.queueKey))" : "entfällt im lokalen Modus"
                    )
                    InfoRow(label: "Zeitzone", value: "Europe/Berlin (Tagesgrenzen wie Server)")
                    InfoRow(label: "Version", value: Bundle.main.versionLabel)
                    Text("Trink-Tracker speichert Host, Key und Zertifikate nur auf diesem Gerät. Keys liegen im Schlüsselbund des Systems.")
                        .trinkText(.bodySmall)
                        .foregroundStyle(c.textSecondary)
                        .padding(.top, TrinkSpacing.sm)
                }
            }
        }
    }
}

private struct InfoRow: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    let value: String

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        HStack(alignment: .top, spacing: TrinkSpacing.sm) {
            Text(label)
                .trinkText(.bodySmall)
                .foregroundStyle(c.textSecondary)
                .frame(width: 110, alignment: .leading)
            Text(value).trinkText(.bodySmall).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension Bundle {
    var versionLabel: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }
}
