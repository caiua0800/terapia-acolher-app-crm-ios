import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

// MARK: - Selo "Serviços financeiros Asaas"
//
// Exigência do playbook do Asaas: aparece em toda tela com movimentação de
// valor. Quando o Asaas liberar o selo homologado (`provider.badgeUrl`), a
// imagem oficial entra no lugar do desenho — sem release novo.

struct SeloAsaas: View {
    var badgeUrl: String?
    var height: CGFloat = 34

    var body: some View {
        if let badgeUrl, let url = URL(string: badgeUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFit().frame(height: height)
                default:
                    desenhado
                }
            }
            .accessibilityLabel("Serviços financeiros Asaas")
        } else {
            desenhado
        }
    }

    private var desenhado: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.primary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Serviços financeiros")
                    .font(Theme.body(9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textSecondary)
                Text("Asaas")
                    .font(Theme.body(13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Serviços financeiros Asaas")
    }
}

// MARK: - Rodapé do provedor (selo + razão social + suporte)

struct GwProviderFooter: View {
    let provider: GwProvider

    var body: some View {
        VStack(spacing: 10) {
            SeloAsaas(badgeUrl: provider.badgeUrl)
            Text("Serviços financeiros prestados por \(provider.legalName).")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 14) {
                contato(icon: "phone", texto: provider.supportPhone, url: telURL)
                contato(icon: "envelope", texto: provider.supportEmail, url: mailURL)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var telURL: URL? {
        URL(string: "tel://\(provider.supportPhone.filter(\.isNumber))")
    }

    private var mailURL: URL? {
        URL(string: "mailto:\(provider.supportEmail)")
    }

    @ViewBuilder
    private func contato(icon: String, texto: String, url: URL?) -> some View {
        if let url {
            Link(destination: url) {
                Label(texto, systemImage: icon)
                    .font(Theme.body(11, weight: .semibold))
                    .foregroundStyle(Theme.primary)
            }
        } else {
            Label(texto, systemImage: icon)
                .font(Theme.body(11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Taxas em duas linhas separadas (regra do playbook)

struct GwFeesCard: View {
    let fees: GwFees
    var title: String = "O QUE É DESCONTADO DE CADA COBRANÇA RECEBIDA"

    var body: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.textSecondary)
                GwValueRow(
                    label: "Taxa de plataforma Terapia Acolher",
                    value: Formatters.brl(fees.platformFixed)
                )
                GwValueRow(
                    label: "Tarifa Pix Asaas",
                    value: Formatters.brl(fees.providerPixFixed)
                )
                Divider().overlay(Theme.border)
                GwValueRow(
                    label: "Total por cobrança",
                    value: Formatters.brl(fees.totalPerCharge),
                    destaque: true
                )
                Text("Saque para a sua chave Pix sem tarifa.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct GwValueRow: View {
    let label: String
    let value: String
    var destaque = false
    var valueColor: Color? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(Theme.body(destaque ? 14 : 13, weight: destaque ? .semibold : .regular))
                .foregroundStyle(destaque ? Theme.textPrimary : Theme.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(Theme.money(destaque ? 15 : 13, weight: destaque ? .bold : .medium))
                .foregroundStyle(valueColor ?? Theme.textPrimary)
                .lineLimit(1)
        }
    }
}

// MARK: - Faixa de ambiente de teste

struct GwSimulationBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hammer")
                .font(.system(size: 12, weight: .semibold))
            Text("Ambiente de teste — valores e transferências são simulados.")
                .font(Theme.body(12, weight: .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.warning)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Estados de conta (análise, recusada, suspensa)

struct GwStateCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let message: String
    var detail: String? = nil

    var body: some View {
        ThemeCard {
            VStack(spacing: 12) {
                Circle()
                    .fill(iconColor.opacity(0.14))
                    .frame(width: 58, height: 58)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(iconColor)
                    )
                Text(title)
                    .font(Theme.serifTitle(20))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Campo de texto do assistente

struct GwField<Field: View>: View {
    let label: String
    var hint: String? = nil
    @ViewBuilder var field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(Theme.body(10, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Theme.textSecondary)
            field()
                .font(Theme.body(15))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.border, lineWidth: 1)
                )
            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Cartão de escolha (PF/PJ)

struct GwChoiceCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Circle()
                    .fill(isSelected ? Theme.primary : Theme.primarySoft)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : Theme.primary)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.body(16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Theme.primary : Theme.border)
            }
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(isSelected ? Theme.primary : Theme.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.pressableSubtle)
    }
}

// MARK: - Badge de status genérico do Gateway

extension StatusBadge {
    static func gwDocument(_ status: GwDocumentStatus) -> StatusBadge {
        switch status {
        case .pending: .init(label: status.label, color: Theme.warning, background: Theme.warningSoft)
        case .approved: .init(label: status.label, color: Theme.success, background: Theme.successSoft)
        case .rejected: .init(label: status.label, color: Theme.danger, background: Theme.dangerSoft)
        }
    }

    static func gwWithdrawal(_ status: GwWithdrawalStatus) -> StatusBadge {
        switch status {
        case .pendingApproval, .processing:
            .init(label: status.label, color: Theme.warning, background: Theme.warningSoft)
        case .done:
            .init(label: status.label, color: Theme.success, background: Theme.successSoft)
        case .failed:
            .init(label: status.label, color: Theme.danger, background: Theme.dangerSoft)
        case .canceled:
            .init(label: status.label, color: Theme.textSecondary, background: Theme.border.opacity(0.5))
        }
    }
}

// MARK: - QR code do Pix (desenhado no aparelho a partir do copia-e-cola)

enum GwQRCode {
    /// `pixQrCodeImage` vem nulo do servidor de propósito: o app desenha.
    static func image(from payload: String, size: CGFloat) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        // "M" tolera sujeira de tela sem inflar o QR a ponto de virar borrão.
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        // Renderiza em 3x o tamanho de exibição: o QR precisa ser nítido na
        // tela do paciente que vai escanear, e ampliar depois borra os módulos.
        let escala = max(1, size * 3 / output.extent.width)
        let ampliado = output.transformed(by: CGAffineTransform(scaleX: escala, y: escala))
        let context = CIContext()
        guard let cg = context.createCGImage(ampliado, from: ampliado.extent) else { return nil }
        return UIImage(cgImage: cg, scale: 3, orientation: .up)
    }
}

struct GwQRCodeView: View {
    let payload: String
    var size: CGFloat = 220

    var body: some View {
        Group {
            if let image = GwQRCode.image(from: payload, size: size) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: size, height: size)
                    .accessibilityLabel("QR code do Pix")
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.background)
                    .frame(width: size, height: size)
                    .overlay(
                        Text("Não foi possível desenhar o QR.\nUse o código copia e cola.")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(12)
                    )
            }
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
    }
}

// MARK: - Botão de copiar com confirmação no próprio controle

struct GwCopyButton: View {
    let title: String
    let value: String
    var icon: String = "doc.on.doc"

    @State private var copiado = false

    var body: some View {
        SecondaryButton(
            title: copiado ? "Copiado!" : title,
            icon: copiado ? "checkmark" : icon,
            tint: copiado ? Theme.success : Theme.textPrimary
        ) {
            UIPasteboard.general.string = value
            Haptics.success()
            withAnimation { copiado = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation { copiado = false }
            }
        }
    }
}
