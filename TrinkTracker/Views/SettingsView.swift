import SwiftUI
import UniformTypeIdentifiers

/// Unterseite „Einstellungen“ (Spec 5): Verbindung, Backup im lokalen Modus,
/// Info. Jede Familie trägt Host und Key selbst ein — nichts ist
/// vorausgefüllt. Erreichbar über das Symbol im Kopf, auch ohne Verbindung.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Unterseitenrahmen("Einstellungen") {
            ConnectionSection()
            if settings.mode == .demo {
                BackupSection().padding(.top, Mh.abstand8)
            }
            InfoSection().padding(.top, Mh.abstand8)
        }
    }
}

// MARK: - Verbindung

private struct ConnectionSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let mode = settings.mode
        VStack(alignment: .leading, spacing: 0) {
            Abschnittskopf("Verbindung")
            ForEach(Array(ConnectionKind.allCases.enumerated()), id: \.element.id) { index, kind in
                if index > 0 { MhTrennlinie() }
                AuswahlZeile(kind.label, gewaehlt: mode.kind == kind) {
                    if kind != mode.kind {
                        settings.setMode(kind == .local ? .demo : ConnectionMode.defaultAuthMode)
                    }
                }
            }

            if mode.isServer {
                Abschnittskopf("Authentifizierung").padding(.top, Mh.abstand6)
                ForEach(Array(ConnectionMode.authModes.enumerated()), id: \.element.id) { index, option in
                    if index > 0 { MhTrennlinie() }
                    AuswahlZeile(option.authLabel, gewaehlt: mode == option) { settings.setMode(option) }
                }

                ServerFields(mode: mode).padding(.top, Mh.abstand6)

                MhTrennlinie().padding(.top, Mh.abstand6)
                Toggle(isOn: Binding(
                    get: { settings.serverUserManagement },
                    set: { settings.setServerUserManagement($0) }
                )) {
                    VStack(alignment: .leading, spacing: Mh.abstand1) {
                        Text("Erweiterte Server-Actions")
                            .font(.custom(MhSchrift.medium, size: 16, relativeTo: .body))
                            .foregroundStyle(Mh.textStrong)
                        Text("Nutzer- und Favoritenverwaltung über die API. Nur einschalten, wenn der Mandant nutzer_anlegen, nutzer_umbenennen, nutzer_loeschen und favorit_loeschen installiert hat.")
                            .mhText(.small)
                            .foregroundStyle(Mh.textSecondary)
                    }
                }
                .tint(Mh.primary)
                .padding(.vertical, Mh.abstand3)
            }
        }
    }
}

/// Felder eines Server-Modus: Basis-URL, Keys, Zertifikat, Verbindungstest.
private struct ServerFields: View {
    @Environment(AppSettings.self) private var settings
    let mode: ConnectionMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BaseUrlField(mode: mode)

            SecretField(
                label: mode == .apiKey ? "API-Key" : "API-Key (optional)",
                helper: mode == .apiKey
                    ? "Wird als X-API-Key gesendet."
                    : "Leer lassen, wenn der Mandant keinen Key erwartet. Dann wird kein X-API-Key-Header gesendet.",
                value: settings.apiKey(for: mode),
                onSave: { settings.setApiKey(mode, $0) }
            )
            .padding(.top, Mh.abstand5)

            if mode == .cloudflare {
                SecretField(
                    label: "CF-Access-Client-Id",
                    helper: "Service Token der Access-Anwendung dieses Hosts (endet üblich auf .access).",
                    value: settings.cfAccessClientId,
                    onSave: { settings.setCfAccessClientId($0) }
                )
                .padding(.top, Mh.abstand5)
                SecretField(
                    label: "CF-Access-Client-Secret",
                    value: settings.cfAccessClientSecret,
                    onSave: { settings.setCfAccessClientSecret($0) }
                )
                .padding(.top, Mh.abstand5)
            }

            if mode == .api {
                CertSection().padding(.top, Mh.abstand5)
            }

            ConnectionTest().padding(.top, Mh.abstand6)
        }
    }
}

/// Kleiner Speichern-Knopf neben einem Feld (Haarlinie, Haken-Symbol).
private struct SpeichernKnopf: View {
    let aktion: () -> Void

    var body: some View {
        Button(action: aktion) {
            MhSymbol("MhCheck")
                .frame(width: Mh.touch, height: Mh.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Mh.textStrong)
        .overlay(
            RoundedRectangle(cornerRadius: Mh.radiusMd, style: .continuous)
                .stroke(Mh.borderStrong, lineWidth: 1)
        )
        .accessibilityLabel("Speichern")
    }
}

/// Basis-URL als Pflegefeld: initial leer, nur ein Formathinweis als
/// Platzhalter, Speichern ohne Neustart (Spec 3.2).
private struct BaseUrlField: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ToastCenter.self) private var toasts
    let mode: ConnectionMode

    @State private var text = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Mh.abstand2) {
            HStack(alignment: .bottom, spacing: Mh.abstand2) {
                // Ohne Modus im Text: Die gewählte Authentifizierung steht
                // direkt darüber.
                TrinkTextField(label: "Basis-URL", text: $text, placeholder: baseUrlPlaceholder, keyboard: .URL, error: error, onSubmit: save)
                SpeichernKnopf(aktion: save)
                    .padding(.bottom, error == nil ? 0 : 22)
            }
            Hinweistext("Eigenes Feld je Modus, ein Wechsel überschreibt nichts. Die Änderung wirkt sofort, die Warteschlange wechselt mit.")
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
    let label: String
    var helper: String?
    let value: String
    let onSave: (String) -> Void

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Mh.abstand2) {
            HStack(alignment: .bottom, spacing: Mh.abstand2) {
                TrinkTextField(label: label, text: $text, secure: true, onSubmit: save)
                SpeichernKnopf(aktion: save)
            }
            if let helper {
                Hinweistext(helper)
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

    @State private var status = "Zertifikatsstatus wird geprüft …"
    @State private var importing: ClientCertificateStore.FileKind?
    @State private var pendingP12: Data?
    @State private var passwordPrompt: TextPrompt?

    var body: some View {
        VStack(alignment: .leading, spacing: Mh.abstand2) {
            FeldLabel("Client-Zertifikat (mTLS)")
            Hinweistext(status)
            FlowLayout {
                Button("client.p12 wählen") { importing = .p12 }.buttonStyle(MhZweitButtonStil(klein: true))
                Button("client.crt wählen") { importing = .cert }.buttonStyle(MhZweitButtonStil(klein: true))
                Button("client.key wählen") { importing = .key }.buttonStyle(MhZweitButtonStil(klein: true))
            }
            Hinweistext("Empfohlen ist eine PKCS#12-Datei (client.p12). Alternativ PEM-Dateien; der Schlüssel muss dann ohne Passwort vorliegen. Die Dateien werden in den App-Ordner kopiert und liegen nicht im Backup der Einstellungen.")
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
            status = "Fehlt: \(missing.joined(separator: " und ")), oder client.p12 (gesucht in \(s.path))"
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

/// „Verbindung testen“ ruft `?action=users` und meldet die Anzahl Nutzer —
/// oder den Fehler samt CF-/Auth-Diagnose (Spec 3.2/3.3). Die eine
/// Hauptaktion dieser Seite in den Server-Modi.
private struct ConnectionTest: View {
    @Environment(AppSettings.self) private var settings

    @State private var busy = false
    @State private var result: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Mh.abstand3) {
            Button(busy ? "Teste …" : "Verbindung testen") { Task { await test() } }
                .buttonStyle(MhHauptButtonStil(breit: true))
                .disabled(busy)
            if let result {
                MhHinweis(result, art: failed ? .fehler : .erfolg)
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
            result = "Verbindung in Ordnung, \(count) Nutzer gefunden."
            failed = false
        } catch {
            result = errorText(error)
            failed = true
        }
        await service.dispose()
        busy = false
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

/// Backup und Export im lokalen Modus. „Exportieren“ ist hier die eine
/// Hauptaktion (der Verbindungstest gibt es nur in den Server-Modi).
private struct BackupSection: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts

    @State private var busy = false
    @State private var exportDocument: JSONBackupDocument?
    @State private var showImporter = false
    @State private var pendingImport: [String: Any]?
    @State private var confirmPrompt: ConfirmPrompt?

    private var exportName: String {
        "trinktracker-backup-\(String(iso8601String(Date()).prefix(10))).json"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Abschnittskopf("Backup und Export")
            Hinweistext("Alle lokalen Daten als JSON sichern oder zurückspielen, auch für den Wechsel zwischen Geräten. Das Format ist zur Flutter-Version kompatibel.")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Mh.abstand3) { knoepfe }
                VStack(spacing: Mh.abstand3) { knoepfe }
            }
            .padding(.top, Mh.abstand4)
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

    @ViewBuilder
    private var knoepfe: some View {
        Button("Exportieren") { Task { await export() } }
            .buttonStyle(MhHauptButtonStil(breit: true))
            .disabled(busy)
        Button("Importieren") { showImporter = true }
            .buttonStyle(MhZweitButtonStil(breit: true))
            .disabled(busy)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Abschnittskopf("Info")
            InfoRow(label: "Modus", value: settings.mode.label)
            MhTrennlinie()
            InfoRow(
                label: "Warteschlange",
                value: settings.mode.isServer ? "\(store.pendingCount) ausstehend (\(settings.queueKey))" : "entfällt im lokalen Modus"
            )
            MhTrennlinie()
            InfoRow(label: "Zeitzone", value: "Europe/Berlin (Tagesgrenzen wie Server)")
            MhTrennlinie()
            InfoRow(label: "Version", value: Bundle.main.versionLabel)
            Hinweistext("Trink-Tracker speichert Host, Key und Zertifikate nur auf diesem Gerät. Keys liegen im Schlüsselbund des Systems.")
                .padding(.top, Mh.abstand4)
        }
    }
}

private struct InfoRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let label: String
    let value: String

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Mh.abstand3))
        layout {
            Text(label)
                .mhText(.small)
                .foregroundStyle(Mh.textSecondary)
                .frame(minWidth: typeSize.isAccessibilitySize ? nil : 110, alignment: .leading)
            Text(value)
                .mhText(.small)
                .foregroundStyle(Mh.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Mh.abstand3)
    }
}

extension Bundle {
    var versionLabel: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }
}
