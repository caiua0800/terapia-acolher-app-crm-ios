import SwiftUI
import UIKit

// MARK: - Feedback tátil

/// Retorno háptico padronizado. Regra do projeto: toda ação que dispara
/// requisição vibra levemente NO toque, antes da resposta do servidor.
enum Haptics {
    /// Último toque disparado. O estilo `.pressable` agora dispara sozinho, e
    /// 32 pontos do app ainda chamam `tap()` na mão — sem esta janela os dois
    /// disparariam junto e o toque viraria um trepidar. Colapsar em vez de
    /// remover as chamadas evita perder o haptic de botões que não usam o
    /// estilo (Documentos e Arquivos ainda têm um caso cada).
    private static var ultimoToque: TimeInterval = 0
    private static let janela: TimeInterval = 0.06

    static func tap() {
        let agora = Date.timeIntervalSinceReferenceDate
        guard agora - ultimoToque > janela else { return }
        ultimoToque = agora
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - Resposta imediata ao toque

/// Encolhe e clareia o controle no instante do toque — a percepção de
/// "respondeu" vem daqui, antes de qualquer resposta de rede.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            // Haptic AQUI cobre de uma vez os 49 botões que usavam o estilo sem
            // pedir o toque na mão — formulários de paciente, cobrança,
            // transação, modelos e grupos não davam retorno nenhum.
            .onChange(of: configuration.isPressed) { _, pressionado in
                if pressionado { Haptics.tap() }
            }
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// `.buttonStyle(.pressable)` — feedback visual instantâneo no toque.
    static var pressable: PressableButtonStyle { PressableButtonStyle() }

    /// Variante para alvos grandes (cards, linhas de lista), onde 0.97 exagera.
    static var pressableSubtle: PressableButtonStyle { PressableButtonStyle(scale: 0.99) }
}

// MARK: - Card

struct ThemeCard<Content: View>: View {
    var padding: CGFloat = Theme.cardPadding
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

// MARK: - Botão primário (verde-sálvia, cheio, arredondado)

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var isLoading = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                // O título continua visível durante o envio: sumir com o texto
                // faz o botão parecer que "trocou de estado" em vez de estar
                // trabalhando. O spinner ocupa o lugar do ícone.
                Text(title).font(Theme.body(16, weight: .semibold))
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if let icon {
                    Image(systemName: icon)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(isEnabled ? Theme.primary : Theme.primary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .animation(.easeInOut(duration: 0.15), value: isLoading)
        }
        .buttonStyle(.pressable)
        .disabled(!isEnabled || isLoading)
    }
}

// MARK: - Botão secundário / de contorno com estado de envio

struct SecondaryButton: View {
    let title: String
    var icon: String? = nil
    var isLoading = false
    var isEnabled = true
    var tint: Color = Theme.textPrimary
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                Text(title).font(Theme.body(15, weight: .semibold))
                if isLoading {
                    ProgressView().controlSize(.small).tint(tint)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.border, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.easeInOut(duration: 0.15), value: isLoading)
        }
        .buttonStyle(.pressable)
        .disabled(!isEnabled || isLoading)
    }
}

// MARK: - "Tentar de novo" padrão dos estados de erro

/// Botão de retry com spinner no próprio controle — sem isso o toque num
/// erro de rede parece não fazer nada até a segunda tentativa responder.
struct RetryButton: View {
    var title: String = "Tentar de novo"
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title).font(Theme.body(15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Theme.primary)
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.15), value: isLoading)
        }
        .buttonStyle(.pressable)
        .disabled(isLoading)
    }
}

// MARK: - Botão de ícone com estado de envio (barras, linhas de lista)

/// Ícone que vira spinner enquanto a requisição está em voo.
struct AsyncIconButton: View {
    let icon: String
    var isLoading = false
    var isEnabled = true
    var tint: Color = Theme.textPrimary
    var size: CGFloat = 15
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            ZStack {
                // Reserva de espaço fixa: o layout não "pula" quando o ícone
                // vira spinner.
                Image(systemName: icon)
                    .font(.system(size: size, weight: .semibold))
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().controlSize(.small).tint(tint)
                }
            }
            .foregroundStyle(isEnabled ? tint : tint.opacity(0.4))
            .frame(minWidth: 28, minHeight: 28)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.15), value: isLoading)
        }
        .buttonStyle(.pressable)
        .disabled(!isEnabled || isLoading)
    }
}

// MARK: - Chip de filtro (Tudo / Ativos / Pago...)

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(label)
                .font(Theme.body(14, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Theme.ink : Theme.surface)
                .foregroundStyle(isSelected ? Color.white : Theme.textPrimary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Theme.border, lineWidth: isSelected ? 0 : 1))
                .animation(.easeOut(duration: 0.18), value: isSelected)
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Tag de grupo de paciente (Adultos, Casal...)

struct GroupTag: View {
    let name: String
    let colorHex: String?

    var body: some View {
        Text(name)
            .font(Theme.body(12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.groupColor(colorHex).opacity(0.18))
            .foregroundStyle(Theme.groupColor(colorHex).darker())
            .clipShape(Capsule())
    }
}

// MARK: - Avatar com inicial

struct InitialAvatar: View {
    let name: String
    var colorHex: String? = nil
    var size: CGFloat = 44

    var body: some View {
        Circle()
            .fill(Theme.groupColor(colorHex))
            .frame(width: size, height: size)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(Theme.serifTitle(size * 0.42))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - FAB (botão flutuante verde, canto inferior direito)

struct FloatingActionButton: View {
    var icon: String = "plus"
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Theme.primary)
                .clipShape(Circle())
                .shadow(color: Theme.primary.opacity(0.4), radius: 10, y: 4)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.92))
    }
}

// MARK: - Card de métrica do dashboard

struct MetricCard: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    var caption: String? = nil
    var captionColor: Color = Theme.success

    var body: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 34, height: 34)
                    .background(iconColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(label.uppercased())
                    .font(Theme.body(11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .tracking(0.6)
                // Valor nunca quebra linha: encolhe pra caber (ex.: receitas altas tipo R$ 12.345,67)
                Text(value)
                    .font(Theme.money(24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                // Linha sempre presente (invisível sem caption) pra todos os cards da grade terem a mesma altura
                Text(caption ?? " ")
                    .font(Theme.body(12, weight: .medium))
                    .foregroundStyle(captionColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .opacity(caption == nil ? 0 : 1)
                    .accessibilityHidden(caption == nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Divisor de lista alinhado ao texto

/// Divisor que começa depois do avatar/ícone e respeita a margem direita —
/// divisor colado na borda da tela quebra o alinhamento óptico da lista.
struct InsetDivider: View {
    var leading: CGFloat = 14 + 40 + 12
    var trailing: CGFloat = 14

    var body: some View {
        Divider()
            .overlay(Theme.border)
            .padding(.leading, leading)
            .padding(.trailing, trailing)
    }
}

// MARK: - Linha de seleção de paciente

/// Linha usada nos seletores "escolha o paciente" (Documentos, Arquivos,
/// Financeiro). Existia uma cópia levemente diferente em cada módulo —
/// avatares sem cor de grupo, paddings e divisores desalinhados.
struct PatientPickerRow: View {
    let name: String
    var colorHex: String? = nil
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            InitialAvatar(name: name, colorHex: colorHex, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Badge de status (Pago / Pendente / Atrasado / Online...)

struct StatusBadge: View {
    let label: String
    let color: Color
    let background: Color

    var body: some View {
        Text(label)
            .font(Theme.body(11, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background)
            .foregroundStyle(color)
            .clipShape(Capsule())
            // Sem isto a badge cede espaço quando o conteúdo ao lado é longo e
            // o rótulo quebra no meio da palavra ("PENDENT/E"). Como o
            // componente é usado no app inteiro, a correção mora aqui.
            .lineLimit(1)
            .fixedSize()
    }

    static func pago() -> StatusBadge { .init(label: "PAGO", color: Theme.success, background: Theme.successSoft) }
    static func pendente() -> StatusBadge { .init(label: "PENDENTE", color: Theme.warning, background: Theme.warningSoft) }
    static func atrasado() -> StatusBadge { .init(label: "ATRASADO", color: Theme.danger, background: Theme.dangerSoft) }
}

// MARK: - Estado vazio

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(Theme.primary.opacity(0.5))
            Text(title)
                .font(Theme.serifTitle(20))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button {
                    Haptics.tap()
                    action()
                } label: {
                    Label(actionTitle, systemImage: "plus")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Theme.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 32)
    }
}

private extension Color {
    /// Escurece a cor pra texto legível sobre fundo claro da mesma matiz.
    func darker() -> Color {
        let ui = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: min(s + 0.15, 1), brightness: max(b - 0.35, 0), opacity: a)
    }
}
