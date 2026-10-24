import SwiftUI

// MARK: - Peças visuais da "Minha Agenda" (Google)
//
// Azul-acinzentado para o compromisso do Google não parecer sessão (verde é
// da Agenda Acolher). Mesmos tons do web (`agenda/origem.tsx`).

enum GoogleAgendaStyle {
    /// Cor dos compromissos do Google.
    static let color = Color(hex: 0x7FA8C9)
    /// Texto sobre o fundo claro (contraste legível; o 7FA8C9 puro fica fraco).
    static let text = Color(hex: 0x4F7A9C)
    /// Texto do bloco na grade da semana.
    static let blockText = Color(hex: 0x3F6684)
    /// Fundo do bloco na grade da semana.
    static let blockFill = Color(hex: 0xEEF4F9)
    static let soft = color.opacity(0.15)
}

/// "G" no lugar do logotipo: o app não carrega marca de terceiros.
struct GoogleAgendaGlyph: View {
    var size: CGFloat = 46

    var body: some View {
        Text("G")
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(GoogleAgendaStyle.color)
            .frame(width: size, height: size)
            .background(GoogleAgendaStyle.color.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: Seletor Agenda Acolher | Minha Agenda | Todos

struct AgendaOriginPicker: View {
    let selection: AgendaOrigin
    let onChange: (AgendaOrigin) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AgendaOrigin.allCases) { origin in
                Button {
                    guard selection != origin else { return }
                    Haptics.tap()
                    onChange(origin)
                } label: {
                    Text(origin.rawValue)
                        .font(Theme.body(13, weight: selection == origin ? .semibold : .regular))
                        .foregroundStyle(selection == origin ? Theme.textPrimary : Theme.textPrimary.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            selection == origin ? Theme.surface : Color.clear,
                            in: Capsule()
                        )
                        .shadow(
                            color: selection == origin ? .black.opacity(0.07) : .clear,
                            radius: 4, y: 2
                        )
                }
                .accessibilityAddTraits(selection == origin ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color(hex: 0xF0EBE2))
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.15), value: selection)
    }
}

// MARK: Compromisso do Google na lista (só leitura, abre no Google Agenda)

struct GoogleAgendaEventListItem: View {
    let event: GoogleAgendaEvent

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            guard let url = event.url else { return }
            Haptics.tap()
            openURL(url)
        } label: {
            ThemeCard(padding: 14) {
                HStack(spacing: 12) {
                    GoogleAgendaGlyph()
                    VStack(alignment: .leading, spacing: 5) {
                        Text(event.title)
                            .font(Theme.body(16, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text("\(event.timeLabel) · Minha Agenda (Google)")
                            .font(Theme.body(12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if event.url != nil {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(GoogleAgendaStyle.text)
                    }
                }
            }
        }
        .buttonStyle(.pressableSubtle)
        .disabled(event.url == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(event.timeLabel), Minha Agenda do Google")
        .accessibilityHint(event.url == nil ? "" : "Abre no Google Agenda")
    }
}

/// Item da linha do tempo: sessão (com as ações de sempre) ou compromisso do Google.
struct AgendaTimelineRow: View {
    let item: AgendaItem

    var body: some View {
        switch item {
        case .session(let session): AgendaSessionListItem(session: session)
        case .google(let event): GoogleAgendaEventListItem(event: event)
        }
    }
}

// MARK: Aviso quando a leitura do Google falha (a agenda continua de pé)

struct GoogleAgendaWarning: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GoogleAgendaStyle.text)
                .padding(.top, 1)
            Text("Não foi possível ler sua agenda do Google agora. Tente de novo em instantes.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}
