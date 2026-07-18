import SwiftUI

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
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(title).font(Theme.body(16, weight: .semibold))
                    if let icon { Image(systemName: icon) }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(isEnabled ? Theme.primary : Theme.primary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 26))
        }
        .disabled(!isEnabled || isLoading)
    }
}

// MARK: - Chip de filtro (Tudo / Ativos / Pago...)

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.body(14, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Theme.ink : Theme.surface)
                .foregroundStyle(isSelected ? Color.white : Theme.textPrimary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Theme.border, lineWidth: isSelected ? 0 : 1))
        }
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
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Theme.primary)
                .clipShape(Circle())
                .shadow(color: Theme.primary.opacity(0.4), radius: 10, y: 4)
        }
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
                Text(value)
                    .font(Theme.money(24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                if let caption {
                    Text(caption)
                        .font(Theme.body(12, weight: .medium))
                        .foregroundStyle(captionColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                Button(action: action) {
                    Label(actionTitle, systemImage: "plus")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Theme.primary)
                        .clipShape(Capsule())
                }
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
