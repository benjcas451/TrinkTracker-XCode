import SwiftUI

// App-eigene Bausteine auf Basis von Minze & Honig 2.0 (Theme/MhTheme.swift,
// Theme/MhBausteine.swift). Farben nur über Rollen (`Mh.*`), keine Hex-Werte.

/// Abschnittskopf (`.section-title`): Caption in Versalien, Dritttextfarbe,
/// rechts optional eine leise Aktion.
struct Abschnittskopf<Rechts: View>: View {
    let text: String
    @ViewBuilder var rechts: () -> Rechts

    init(_ text: String, @ViewBuilder rechts: @escaping () -> Rechts = { EmptyView() }) {
        self.text = text
        self.rechts = rechts
    }

    var body: some View {
        HStack(alignment: .center, spacing: Mh.abstand3) {
            Text(text.uppercased())
                .mhText(.caption)
                .foregroundStyle(Mh.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            rechts()
        }
        .frame(minHeight: 24)
        .padding(.bottom, Mh.abstand2)
    }
}

/// Feldlabel über einer Gruppe von Bedienelementen (wie `.field-label`).
struct FeldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text).mhText(.label).foregroundStyle(Mh.textStrong)
    }
}

/// Nebentext unter einem Abschnitt (`.hint`).
struct Hinweistext: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .mhText(.small)
            .foregroundStyle(Mh.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Auswahlzeile in Listen (Verbindung, Authentifizierung): Text links, Haken
/// in primary bei der gewählten Option. Skaliert mit Dynamic Type.
struct AuswahlZeile: View {
    let text: String
    let gewaehlt: Bool
    let aktion: () -> Void

    init(_ text: String, gewaehlt: Bool, aktion: @escaping () -> Void) {
        self.text = text
        self.gewaehlt = gewaehlt
        self.aktion = aktion
    }

    var body: some View {
        Button(action: aktion) {
            HStack(spacing: Mh.abstand3) {
                Text(text)
                    .font(.custom(gewaehlt ? MhSchrift.medium : MhSchrift.regular, size: 16, relativeTo: .body))
                    .foregroundStyle(gewaehlt ? Mh.textStrong : Mh.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if gewaehlt {
                    MhSymbol("MhCheck").foregroundStyle(Mh.primary)
                }
            }
            .padding(.vertical, Mh.abstand2)
            .frame(minHeight: Mh.touch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(gewaehlt ? [.isSelected] : [])
    }
}

/// Offline-Hinweis mit der Anzahl ausstehender Aktionen (Spec 5, Screen 1).
struct OfflineBanner: View {
    let isOffline: Bool
    let pendingCount: Int
    var onRetry: (() -> Void)?

    private var text: String {
        let aktionen = pendingCount == 1
            ? "1 Aktion wartet auf Übertragung."
            : "\(pendingCount) Aktionen warten auf Übertragung."
        if isOffline {
            return pendingCount > 0 ? "Offline, letzter Stand. \(aktionen)" : "Offline. Angezeigt wird der letzte erfolgreiche Stand."
        }
        return aktionen
    }

    var body: some View {
        if isOffline || pendingCount > 0 {
            VStack(alignment: .leading, spacing: 0) {
                MhHinweis(text, art: .warnung, symbol: "MhCloudOff")
                if let onRetry {
                    Button("Erneut senden", action: onRetry)
                        .buttonStyle(.mhText)
                }
            }
            .padding(.bottom, Mh.abstand4)
        }
    }
}

/// Eingabefeld (`.field` + `input`): Label darüber, 44 pt, Radius 10,
/// Haarlinie `borderStrong`, Grund `fieldBg`; Einheit rechts im Feld.
struct TrinkTextField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var suffix: String?
    var keyboard: UIKeyboardType = .default
    var secure = false
    var maxLength: Int?
    var error: String?
    var onSubmit: (() -> Void)?

    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).mhText(.label).foregroundStyle(Mh.textStrong)
            HStack(spacing: Mh.abstand2) {
                Group {
                    if secure && !revealed {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .mhText(.body)
                .foregroundStyle(Mh.text)
                .tint(Mh.primary)
                .keyboardType(keyboard)
                .textInputAutocapitalization(secure || keyboard == .URL ? .never : .sentences)
                .autocorrectionDisabled(secure || keyboard == .URL)
                .onSubmit { onSubmit?() }
                .onChange(of: text) { _, newValue in
                    if let maxLength, newValue.count > maxLength {
                        text = String(newValue.prefix(maxLength))
                    }
                }
                if let suffix {
                    Text(suffix)
                        .mhText(.small)
                        .foregroundStyle(Mh.textSecondary)
                }
                if secure {
                    Button {
                        revealed.toggle()
                    } label: {
                        MhSymbol(revealed ? "MhEyeOff" : "MhEye")
                            .foregroundStyle(Mh.textSecondary)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(revealed ? "Verbergen" : "Anzeigen")
                }
            }
            .padding(.horizontal, Mh.abstand3)
            .padding(.vertical, Mh.abstand2)
            .frame(minHeight: Mh.touch)
            .background(RoundedRectangle(cornerRadius: Mh.radiusMd, style: .continuous).fill(Mh.fieldBg))
            .overlay(
                RoundedRectangle(cornerRadius: Mh.radiusMd, style: .continuous)
                    .stroke(error == nil ? Mh.borderStrong : Mh.danger, lineWidth: 1)
            )
            if let error {
                Text(error)
                    .mhText(.small)
                    .foregroundStyle(Mh.danger)
            }
        }
    }
}

/// Zeilenweise fließende Elemente (Flutter `Wrap`). Ein Element, das breiter
/// als die Zeile wäre, bekommt die Zeilenbreite angeboten (große Schrift).
struct FlowLayout: Layout {
    var spacing: CGFloat = Mh.abstand2

    private func groesse(_ subview: LayoutSubview, maxBreite: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard maxBreite.isFinite, maxBreite > 0, ideal.width > maxBreite else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: maxBreite, height: nil))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = groesse(subview, maxBreite: width)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: width == .infinity ? maxX : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = groesse(subview, maxBreite: bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Kurze Rückmeldungen (Toast)

struct Toast: Equatable, Sendable {
    let message: String
    let isError: Bool
}

@Observable
@MainActor
final class ToastCenter {
    private(set) var current: Toast?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    /// Kurze Rückmeldung; Fehler bleiben etwas länger stehen.
    func show(_ message: String, isError: Bool = false) {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            current = Toast(message: message, isError: isError)
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(isError ? 4 : 2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { self?.current = nil }
        }
    }

    /// `nil` als Erfolg, sonst Fehlertext — passend zu `AppStore.run`.
    func result(_ error: String?, success: String) {
        show(error ?? success, isError: error != nil)
    }
}

/// Toast (`.toast`): dunkel auf hell bzw. hell auf dunkel, unten mittig.
struct ToastOverlay: View {
    let toast: Toast?

    var body: some View {
        VStack {
            Spacer()
            if let toast {
                HStack(alignment: .top, spacing: Mh.abstand2) {
                    MhSymbol(toast.isError ? "MhAlert" : "MhCheck", groesse: Mh.symbolKlein)
                        .padding(.top, 2)
                    Text(toast.message)
                        .mhText(.small)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Mh.bg)
                .padding(.horizontal, Mh.abstand4)
                .padding(.vertical, Mh.abstand3)
                .background(
                    RoundedRectangle(cornerRadius: Mh.radiusMd, style: .continuous)
                        .fill(Mh.textStrong)
                        .shadow(color: Color.black.opacity(0.08), radius: 10, y: 6)
                )
                .padding(.horizontal, Mh.rand)
                .padding(.bottom, Mh.abstand2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }
}
