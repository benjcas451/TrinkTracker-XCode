import SwiftUI

/// Karte mit Border statt Schatten (Spec 7).
struct TrinkCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme

    var padding: EdgeInsets = EdgeInsets(top: TrinkSpacing.lg, leading: TrinkSpacing.lg, bottom: TrinkSpacing.lg, trailing: TrinkSpacing.lg)
    var color: Color?
    var onTap: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        let shape = RoundedRectangle(cornerRadius: TrinkRadii.md, style: .continuous)
        let card = content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color ?? c.surface)
            .clipShape(shape)
            .overlay(shape.stroke(c.border, lineWidth: c.borderWidth))

        if let onTap {
            Button(action: onTap) { card }
                .buttonStyle(.plain)
        } else {
            card
        }
    }
}

extension EdgeInsets {
    static func symmetric(horizontal: CGFloat, vertical: CGFloat) -> EdgeInsets {
        EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }

    static func all(_ value: CGFloat) -> EdgeInsets {
        EdgeInsets(top: value, leading: value, bottom: value, trailing: value)
    }
}

struct SectionTitle<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ text: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center) {
            Text(text)
                .trinkText(.titleMedium)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.bottom, TrinkSpacing.sm)
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ text: String) {
        self.init(text) { EmptyView() }
    }
}

/// Fortschrittsbalken: grün-300, ab 100 % honig-300 (Spec 7).
struct GoalProgressBar: View {
    @Environment(\.colorScheme) private var scheme
    let stats: TodayStats
    var height: CGFloat = 10

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        let value = min(max(Double(stats.fortschrittPct ?? 0) / 100, 0), 1)
        let fill = stats.zielErreicht ? c.yellow300 : c.green300
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(c.subtle)
                Capsule().fill(fill).frame(width: geo.size.width * value)
            }
        }
        .frame(height: height)
        .accessibilityLabel(stats.fortschrittPct.map { "\($0) Prozent des Tagesziels" } ?? "Kein Tagesziel")
    }
}

/// Offline-Banner mit der Anzahl ausstehender Aktionen (Spec 5, Screen 1).
struct OfflineBanner: View {
    @Environment(\.colorScheme) private var scheme
    let isOffline: Bool
    let pendingCount: Int
    var onRetry: (() -> Void)?

    private var text: String {
        let aktionen = "\(pendingCount) Aktion\(pendingCount == 1 ? "" : "en") wartet auf Übertragung."
        if isOffline {
            return pendingCount > 0 ? "Offline — letzter Stand. \(aktionen)" : "Offline — angezeigt wird der letzte erfolgreiche Stand."
        }
        return aktionen
    }

    var body: some View {
        if isOffline || pendingCount > 0 {
            let c = TrinkPalette.resolve(scheme)
            HStack(spacing: TrinkSpacing.md) {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 18))
                    .foregroundStyle(c.text)
                Text(text)
                    .trinkText(.bodySmall)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let onRetry {
                    Button("Erneut senden", action: onRetry)
                        .buttonStyle(.trinkText)
                }
            }
            .padding(.symmetric(horizontal: TrinkSpacing.lg, vertical: TrinkSpacing.md))
            .background(c.warningBg)
            .clipShape(RoundedRectangle(cornerRadius: TrinkRadii.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: TrinkRadii.sm, style: .continuous).stroke(c.border, lineWidth: 1.5))
            .padding(.bottom, TrinkSpacing.lg)
        }
    }
}

/// Fehlerfläche mit Symbol.
struct ErrorBox: View {
    @Environment(\.colorScheme) private var scheme
    let message: String

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        HStack(alignment: .top, spacing: TrinkSpacing.md) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 18))
                .foregroundStyle(c.danger)
            Text(message)
                .trinkText(.bodySmall)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(TrinkSpacing.lg)
        .background(c.errorBg)
        .clipShape(RoundedRectangle(cornerRadius: TrinkRadii.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TrinkRadii.sm, style: .continuous).stroke(c.border, lineWidth: 1.5))
    }
}

enum TrinkChipTone { case neutral, favorite }

/// Auswahl-Chip im Pillenformat, Mindesthöhe 44 pt.
struct TrinkChip: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    var selected = false
    var tone: TrinkChipTone = .neutral
    let action: () -> Void

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        let background: Color = switch tone {
        case .neutral: selected ? c.green300 : c.surface
        case .favorite: c.yellow300
        }
        let foreground: Color = switch tone {
        case .neutral: selected ? c.green900 : c.text
        case .favorite: c.yellow900
        }
        let borderColor = (tone == .favorite || selected) ? Color.clear : c.border

        Text(label)
            .trinkText(.labelLarge, tabular: true)
            .foregroundStyle(foreground)
            .padding(.horizontal, TrinkSpacing.lg)
            .frame(minHeight: TrinkSpacing.minTouch)
            .background(background)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(borderColor, lineWidth: c.borderWidth))
            .contentShape(Capsule())
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Meldung mit Aktion für leere Zustände.
struct EmptyHint<Action: View>: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    var description: String?
    @ViewBuilder var action: () -> Action

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        TrinkCard(color: c.subtle) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).trinkText(.titleMedium)
                if let description {
                    Text(description)
                        .trinkText(.bodySmall)
                        .foregroundStyle(c.textSecondary)
                        .padding(.top, TrinkSpacing.sm)
                }
                action()
                    .padding(.top, TrinkSpacing.lg)
            }
        }
    }
}

extension EmptyHint where Action == EmptyView {
    init(title: String, description: String? = nil) {
        self.init(title: title, description: description) { EmptyView() }
    }
}

/// Eingabefeld im Stil des Themes: Label oben, gefüllte Fläche, Border.
struct TrinkTextField: View {
    @Environment(\.colorScheme) private var scheme
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
        let c = TrinkPalette.resolve(scheme)
        VStack(alignment: .leading, spacing: TrinkSpacing.xs) {
            Text(label)
                .trinkText(.labelMedium)
                .foregroundStyle(c.textSecondary)
            HStack(spacing: TrinkSpacing.sm) {
                Group {
                    if secure && !revealed {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .trinkText(.bodyMedium)
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
                        .trinkText(.bodySmall)
                        .foregroundStyle(c.textSecondary)
                }
                if secure {
                    Button {
                        revealed.toggle()
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .foregroundStyle(c.textSecondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(revealed ? "Verbergen" : "Anzeigen")
                }
            }
            .padding(.symmetric(horizontal: TrinkSpacing.lg, vertical: TrinkSpacing.md))
            .frame(minHeight: TrinkSpacing.minTouch)
            .background(c.subtle)
            .clipShape(RoundedRectangle(cornerRadius: TrinkRadii.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TrinkRadii.sm, style: .continuous)
                    .stroke(error == nil ? c.border : c.red600, lineWidth: error == nil ? c.borderWidth : 1.5)
            )
            if let error {
                Text(error)
                    .trinkText(.bodySmall)
                    .foregroundStyle(c.danger)
            }
        }
    }
}

/// Zeilenweise fließende Chips (Flutter `Wrap`).
struct FlowLayout: Layout {
    var spacing: CGFloat = TrinkSpacing.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
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
            let size = subview.sizeThatFits(.unspecified)
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

// MARK: - Kurze Rückmeldungen (Flutter SnackBar)

struct Toast: Equatable, Sendable {
    let message: String
    let isError: Bool
}

@Observable
@MainActor
final class ToastCenter {
    private(set) var current: Toast?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    /// Kurze Rückmeldung; Fehler in der Fehlerfläche, Erfolg neutral.
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

struct ToastOverlay: View {
    @Environment(\.colorScheme) private var scheme
    let toast: Toast?

    var body: some View {
        let c = TrinkPalette.resolve(scheme)
        VStack {
            Spacer()
            if let toast {
                Text(toast.message)
                    .trinkText(.bodyMedium)
                    .foregroundStyle(c.text)
                    .padding(.symmetric(horizontal: TrinkSpacing.lg, vertical: TrinkSpacing.md))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(toast.isError ? c.errorBg : c.successBg)
                    .clipShape(RoundedRectangle(cornerRadius: TrinkRadii.sm, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: TrinkRadii.sm, style: .continuous).stroke(c.border, lineWidth: 1.5))
                    .padding(.horizontal, TrinkSpacing.lg)
                    .padding(.bottom, TrinkSpacing.sm)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .allowsHitTesting(false)
    }
}
