import Foundation
import Security

/// Quelle für das mTLS-Client-Zertifikat (Spec 3.4).
///
/// Unterstützt werden zwei Formen im Ordner `Documents/certs` (über die
/// Dateien-App erreichbar, `UIFileSharingEnabled`):
///
/// * `client.p12` — PKCS#12 mit Zertifikat und Schlüssel; das Passwort wird
///   beim Import abgefragt und im Schlüsselbund abgelegt. Der robuste Weg.
/// * `client.crt` + `client.key` — PEM wie bei der Flutter-App. Der Schlüssel
///   muss unpasswortiert sein (PKCS#8 oder PKCS#1/SEC1, RSA oder EC).
///
/// Die Identity wird beim ersten Request aufgebaut und danach gehalten.
final class ClientCertificateStore: @unchecked Sendable {
    static let certFileName = "client.crt"
    static let keyFileName = "client.key"
    static let p12FileName = "client.p12"
    static let p12PasswordKey = "mtlsP12Password"
    private static let keychainLabel = "trinktracker.mtls.client"
    private static let keyTag = Data("trinktracker.mtls.client.key".utf8)

    enum FileKind { case cert, key, p12 }

    struct Status: Sendable {
        let cert: Bool
        let key: Bool
        let p12: Bool
        let path: String

        var isComplete: Bool { p12 || (cert && key) }
    }

    struct Identity {
        let identity: SecIdentity
        let chain: [SecCertificate]
    }

    let folderPath: String?
    private let lock = NSLock()
    private var cached: Identity?

    init(folderPath: String? = nil) {
        self.folderPath = folderPath
    }

    static func appCertDirectory() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("certs", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func directory() throws -> URL {
        if let folder = folderPath?.trimmingCharacters(in: .whitespaces), !folder.isEmpty {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: folder, isDirectory: true)
            }
        }
        return try Self.appCertDirectory()
    }

    /// Welche Dateien liegen im aktuell konfigurierten Ordner?
    func status() -> Status {
        guard let dir = try? directory() else {
            return Status(cert: false, key: false, p12: false, path: "–")
        }
        let fm = FileManager.default
        return Status(
            cert: fm.fileExists(atPath: dir.appendingPathComponent(Self.certFileName).path),
            key: fm.fileExists(atPath: dir.appendingPathComponent(Self.keyFileName).path),
            p12: fm.fileExists(atPath: dir.appendingPathComponent(Self.p12FileName).path),
            path: dir.path
        )
    }

    /// Schreibt den Inhalt einer ausgewählten Datei in den App-Ordner und
    /// verwirft gespeicherte Identities. Liefert den Ordnerpfad.
    @discardableResult
    static func importBytes(_ data: Data, kind: FileKind, p12Password: String? = nil) throws -> String {
        let dir = try appCertDirectory()
        let name: String
        switch kind {
        case .cert: name = certFileName
        case .key: name = keyFileName
        case .p12:
            name = p12FileName
            // Erst prüfen, ob Passwort und Datei zusammenpassen.
            _ = try loadP12(data, password: p12Password ?? "")
            KeychainStore().write(p12PasswordKey, p12Password ?? "")
        }
        try data.write(to: dir.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        // Ein neues PEM-Paar macht ein altes p12 ungültig und umgekehrt.
        if kind != .p12 {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(p12FileName))
        }
        clearKeychainIdentity()
        return dir.path
    }

    /// Lädt die Identity beim ersten Request und hält sie danach — idempotent.
    func identity() throws -> Identity {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }

        let dir = try directory()
        let p12URL = dir.appendingPathComponent(Self.p12FileName)
        let certURL = dir.appendingPathComponent(Self.certFileName)
        let keyURL = dir.appendingPathComponent(Self.keyFileName)
        let fm = FileManager.default

        let built: Identity
        if fm.fileExists(atPath: p12URL.path) {
            let data = try Data(contentsOf: p12URL)
            let password = KeychainStore().read(Self.p12PasswordKey) ?? ""
            built = try Self.loadP12(data, password: password)
        } else if fm.fileExists(atPath: certURL.path), fm.fileExists(atPath: keyURL.path) {
            built = try Self.buildFromPEM(cert: try Data(contentsOf: certURL), key: try Data(contentsOf: keyURL))
        } else {
            throw TrinkError(
                .configuration,
                "Client-Zertifikat nicht gefunden. Erwartet werden \(Self.certFileName) und \(Self.keyFileName) "
                    + "(oder \(Self.p12FileName)) in \(dir.path)."
            )
        }
        cached = built
        return built
    }

    // MARK: PKCS#12

    private static func loadP12(_ data: Data, password: String) throws -> Identity {
        var items: CFArray?
        let options: [String: Any] = [kSecImportExportPassphrase as String: password]
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess,
              let array = items as? [[String: Any]], let first = array.first,
              let identityRef = first[kSecImportItemIdentity as String] else {
            let hint = status == errSecAuthFailed ? "Passwort falsch." : "Status \(status)."
            throw TrinkError(.configuration, "client.p12 konnte nicht gelesen werden. \(hint)")
        }
        let identity = identityRef as! SecIdentity
        var chain = (first[kSecImportItemCertChain as String] as? [SecCertificate]) ?? []
        if !chain.isEmpty { chain.removeFirst() } // erstes Element ist das Client-Zertifikat selbst
        return Identity(identity: identity, chain: chain)
    }

    // MARK: PEM

    private static func buildFromPEM(cert certPEM: Data, key keyPEM: Data) throws -> Identity {
        let certBlocks = PEM.blocks(in: certPEM, label: "CERTIFICATE")
        guard let leafDER = certBlocks.first, let leaf = SecCertificateCreateWithData(nil, leafDER as CFData) else {
            throw TrinkError(.configuration, "client.crt enthält kein lesbares Zertifikat (PEM erwartet).")
        }
        let chain = certBlocks.dropFirst().compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        let key = try privateKey(fromPEM: keyPEM)

        clearKeychainIdentity()
        let accessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let keyAdd: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecValueRef as String: key,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrLabel as String: keychainLabel,
            kSecAttrAccessible as String: accessible,
        ]
        let keyStatus = SecItemAdd(keyAdd as CFDictionary, nil)
        guard keyStatus == errSecSuccess || keyStatus == errSecDuplicateItem else {
            throw TrinkError(.configuration, "Privater Schlüssel konnte nicht im Schlüsselbund abgelegt werden (\(keyStatus)).")
        }
        let certAdd: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: leaf,
            kSecAttrLabel as String: keychainLabel,
            kSecAttrAccessible as String: accessible,
        ]
        let certStatus = SecItemAdd(certAdd as CFDictionary, nil)
        guard certStatus == errSecSuccess || certStatus == errSecDuplicateItem else {
            throw TrinkError(.configuration, "Zertifikat konnte nicht im Schlüsselbund abgelegt werden (\(certStatus)).")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: keychainLabel,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let result else {
            throw TrinkError(
                .configuration,
                "Zertifikat und Schlüssel passen nicht zusammen oder konnten nicht verknüpft werden (\(status)). "
                    + "Alternativ beide als client.p12 importieren."
            )
        }
        return Identity(identity: result as! SecIdentity, chain: Array(chain))
    }

    private static func clearKeychainIdentity() {
        SecItemDelete([kSecClass as String: kSecClassIdentity, kSecAttrLabel as String: keychainLabel] as CFDictionary)
        SecItemDelete([kSecClass as String: kSecClassCertificate, kSecAttrLabel as String: keychainLabel] as CFDictionary)
        SecItemDelete([kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: keyTag] as CFDictionary)
    }

    /// PEM-Schlüssel → `SecKey`. Erkennt PKCS#8, PKCS#1 (RSA) und SEC1 (EC).
    private static func privateKey(fromPEM pem: Data) throws -> SecKey {
        let text = String(decoding: pem, as: UTF8.self)
        if text.contains("ENCRYPTED") {
            throw TrinkError(.configuration, "client.key ist verschlüsselt — der Schlüssel muss ohne Passwort vorliegen.")
        }

        let keyType: CFString
        let keyData: Data
        if let pkcs8 = PEM.blocks(in: pem, label: "PRIVATE KEY").first {
            let info = try DER.parsePKCS8(pkcs8)
            switch info.algorithm {
            case .rsa:
                keyType = kSecAttrKeyTypeRSA
                keyData = info.key
            case .ec:
                keyType = kSecAttrKeyTypeECSECPrimeRandom
                keyData = try DER.x963(fromSEC1: info.key)
            }
        } else if let pkcs1 = PEM.blocks(in: pem, label: "RSA PRIVATE KEY").first {
            keyType = kSecAttrKeyTypeRSA
            keyData = pkcs1
        } else if let sec1 = PEM.blocks(in: pem, label: "EC PRIVATE KEY").first {
            keyType = kSecAttrKeyTypeECSECPrimeRandom
            keyData = try DER.x963(fromSEC1: sec1)
        } else {
            throw TrinkError(.configuration, "client.key enthält keinen erkennbaren privaten Schlüssel (PEM erwartet).")
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: keyType,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            let reason = error?.takeRetainedValue().localizedDescription ?? "unbekannt"
            throw TrinkError(.configuration, "client.key konnte nicht geladen werden: \(reason)")
        }
        return key
    }
}

// MARK: - PEM / DER Helfer

enum PEM {
    /// Alle DER-Blöcke mit dem angegebenen Label (`-----BEGIN <label>-----`).
    static func blocks(in data: Data, label: String) -> [Data] {
        let text = String(decoding: data, as: UTF8.self)
        let begin = "-----BEGIN \(label)-----"
        let end = "-----END \(label)-----"
        var result: [Data] = []
        var search = text.startIndex
        while let start = text.range(of: begin, range: search..<text.endIndex),
              let stop = text.range(of: end, range: start.upperBound..<text.endIndex) {
            let body = text[start.upperBound..<stop.lowerBound]
                .split(whereSeparator: \.isNewline)
                .filter { !$0.contains(":") } // Header wie Proc-Type überspringen
                .joined()
            if let der = Data(base64Encoded: body, options: [.ignoreUnknownCharacters]) {
                result.append(der)
            }
            search = stop.upperBound
        }
        return result
    }
}

enum DER {
    enum Algorithm { case rsa, ec }

    struct PKCS8Info {
        let algorithm: Algorithm
        let key: Data
    }

    struct Element {
        let tag: UInt8
        let content: Data
    }

    private static let rsaOID = Data([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])
    private static let ecOID = Data([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01])

    private static func failure(_ what: String) -> TrinkError {
        TrinkError(.configuration, "client.key: \(what) — erwartet wird PKCS#8, PKCS#1 oder SEC1 (unverschlüsselt).")
    }

    /// Liest nacheinander alle TLV-Elemente einer DER-Sequenz.
    static func elements(_ data: Data) throws -> [Element] {
        var result: [Element] = []
        var i = data.startIndex
        while i < data.endIndex {
            let tag = data[i]
            i += 1
            guard i < data.endIndex else { throw failure("Struktur unvollständig") }
            var length = Int(data[i])
            i += 1
            if length & 0x80 != 0 {
                let count = length & 0x7F
                guard count > 0, count <= 4, i + count <= data.endIndex else { throw failure("Längenfeld ungültig") }
                length = 0
                for _ in 0..<count {
                    length = (length << 8) | Int(data[i])
                    i += 1
                }
            }
            guard i + length <= data.endIndex else { throw failure("Länge überschreitet Daten") }
            result.append(Element(tag: tag, content: data.subdata(in: i..<(i + length))))
            i += length
        }
        return result
    }

    static func parsePKCS8(_ der: Data) throws -> PKCS8Info {
        guard let outer = try elements(der).first, outer.tag == 0x30 else { throw failure("keine Sequenz") }
        let parts = try elements(outer.content)
        guard parts.count >= 3, parts[1].tag == 0x30, parts[2].tag == 0x04 else { throw failure("PKCS#8-Aufbau unerwartet") }
        guard let oid = try elements(parts[1].content).first, oid.tag == 0x06 else { throw failure("Algorithmus fehlt") }
        let algorithm: Algorithm
        if oid.content == rsaOID {
            algorithm = .rsa
        } else if oid.content == ecOID {
            algorithm = .ec
        } else {
            throw failure("Algorithmus wird nicht unterstützt (nur RSA und EC)")
        }
        return PKCS8Info(algorithm: algorithm, key: parts[2].content)
    }

    /// SEC1 `ECPrivateKey` → X9.63 (`04 || X || Y || K`), wie `SecKeyCreateWithData` es erwartet.
    static func x963(fromSEC1 der: Data) throws -> Data {
        guard let outer = try elements(der).first, outer.tag == 0x30 else { throw failure("keine Sequenz") }
        let parts = try elements(outer.content)
        guard parts.count >= 2, parts[1].tag == 0x04 else { throw failure("EC-Schlüssel unerwartet aufgebaut") }
        var scalar = parts[1].content
        guard let pubElement = parts.first(where: { $0.tag == 0xA1 }),
              let bitString = try elements(pubElement.content).first, bitString.tag == 0x03, bitString.content.count > 1 else {
            throw failure("öffentlicher Punkt fehlt im EC-Schlüssel")
        }
        let point = bitString.content.dropFirst() // erstes Byte: ungenutzte Bits
        guard point.first == 0x04 else { throw failure("EC-Punkt ist nicht unkomprimiert") }
        let coordinateSize = (point.count - 1) / 2
        if scalar.count < coordinateSize {
            scalar = Data(repeating: 0, count: coordinateSize - scalar.count) + scalar
        } else if scalar.count > coordinateSize {
            scalar = scalar.suffix(coordinateSize)
        }
        return Data(point) + scalar
    }
}
