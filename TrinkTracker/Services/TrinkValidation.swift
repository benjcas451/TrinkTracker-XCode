import Foundation

/// Dieselben Grenzen wie die serverseitige Validierung (Spec 2), damit der
/// lokale Modus und die Offline-Warteschlange nichts durchlassen, was der
/// Server später ablehnen würde.
enum TrinkValidation {
    static let getraenkMaxLength = 60
    static let mengeMin = 1
    static let mengeMax = 10000
    static let tageszielMin = 0
    static let tageszielMax = 20000
    static let nameMaxLength = 50

    static func getraenk(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw TrinkError(.validation, "Getränk darf nicht leer sein.")
        }
        if trimmed.count > getraenkMaxLength {
            throw TrinkError(.validation, "Getränk darf höchstens \(getraenkMaxLength) Zeichen haben.")
        }
        return trimmed
    }

    static func menge(_ value: Int) throws -> Int {
        if value < mengeMin || value > mengeMax {
            throw TrinkError(.validation, "Menge muss zwischen \(mengeMin) und \(mengeMax) ml liegen.")
        }
        return value
    }

    static func tagesziel(_ value: Int) throws -> Int {
        if value < tageszielMin || value > tageszielMax {
            throw TrinkError(
                .validation,
                "Tagesziel muss zwischen \(tageszielMin) und \(tageszielMax) ml liegen (0 schaltet das Ziel aus)."
            )
        }
        return value
    }

    static func userName(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw TrinkError(.validation, "Name darf nicht leer sein.")
        }
        if trimmed.count > nameMaxLength {
            throw TrinkError(.validation, "Name darf höchstens \(nameMaxLength) Zeichen haben.")
        }
        return trimmed
    }

    /// `create_time` darf nicht in der Zukunft liegen (Spec 2).
    static func createTime(_ value: Date, now: Date = Date()) throws -> Date {
        if value > now.addingTimeInterval(60) {
            throw TrinkError(.validation, "Zeitpunkt darf nicht in der Zukunft liegen.")
        }
        return value
    }
}
