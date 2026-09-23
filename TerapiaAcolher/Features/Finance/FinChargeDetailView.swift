import Observation
import SwiftUI

@Observable
@MainActor
final class FinChargeDetailModel {
    var charge: FinCharge
    /// Flag separada: com uma só, o spinner acenderia no botão errado.
    var isWorkingPix = false
    var alerta: String?
    var showAlerta = false
    var gatewayPix: GwCharge?

    init(charge: FinCharge) {
        self.charge = charge
    }

    /// Link do caminho antigo (conta Asaas própria). Só cobrança criada antes
    /// do Acolher Financeiro tem isso; hoje só o gateway cobra.
    var linkAntigo: String? {
        guard charge.gatewayName != "ACOLHER",
              let url = charge.gatewayInvoiceUrl, !url.isEmpty else { return nil }
        return url
    }

    var emAberto: Bool { charge.status == .pending || charge.status == .overdue }

    func carregar() async {
        if let atual = try? await FinanceAPI.charges(patientId: charge.patientId)
            .first(where: { $0.id == charge.id }) {
            charge = atual
        }
    }

    /// Pix pelo Acolher Financeiro — caminho principal de quem tem conta aprovada.
    func pixDoGateway() async {
        isWorkingPix = true
        defer { isWorkingPix = false }
        do {
            gatewayPix = charge.gatewayName == "ACOLHER"
                ? try await FinGatewayAPI.charge(chargeId: charge.id)
                : try await FinGatewayAPI.createPix(chargeId: charge.id)
            Haptics.success()
            await carregar()
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch let error as APIError {
            present(error.message)
        } catch {
            present("Não foi possível gerar o Pix. Verifique sua conexão.")
        }
    }

    private func present(_ m: String) {
        alerta = m
        showAlerta = true
    }
}

/// Página da cobrança.
///
/// Esta tela não existia: tocar na linha da lista não fazia nada, e todas as
/// ações viviam escondidas atrás dos três pontinhos — inclusive o link de
/// pagamento, que é justamente o que o terapeuta abre a cobrança para pegar.
struct FinChargeDetailView: View {
    @State private var model: FinChargeDetailModel
    @State private var store = FinGatewayStore.shared
    var onChange: () -> Void

    init(charge: FinCharge, onChange: @escaping () -> Void) {
        _model = State(initialValue: FinChargeDetailModel(charge: charge))
        self.onChange = onChange
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    cabecalho
                    dados
                    if model.emAberto { acoes }

                    // O selo não pode depender de conta aprovada: a tela mostra
                    // valor e status de cobrança de qualquer jeito.
                    GwProviderFooter(provider: store.overview?.provider ?? .asaasPadrao)
                }
                .padding(Theme.screenPadding)
                .padding(.bottom, 32)
            }
        }
        .setToolbarTitle("Cobrança")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.carregar()
            await store.load(showSpinner: false)
        }
        .refreshable { await model.carregar() }
        .alert("Ops", isPresented: $model.showAlerta) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alerta ?? "Algo deu errado.")
        }
        .sheet(item: $model.gatewayPix) { pix in
            FinGatewayChargePixSheet(
                charge: pix,
                simulation: store.simulation,
                provider: store.overview?.provider
            ) {
                Task { await model.carregar() }
                onChange()
            }
        }
    }

    private var cabecalho: some View {
        VStack(spacing: 10) {
            Text(Formatters.brl(model.charge.amount))
                .font(Theme.moneyDisplay(34))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 6) {
                StatusBadge(
                    label: rotuloStatus,
                    color: corStatus,
                    background: corStatus.opacity(0.14)
                )
                if model.charge.gatewayName == "ACOLHER",
                   model.charge.status != .paid, model.charge.status != .canceled {
                    StatusBadge(label: "PIX GERADO", color: Theme.primary, background: Theme.primarySoft)
                }
            }

            if let nome = model.charge.patient?.name {
                Text(nome)
                    .font(Theme.body(15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.top, 6)
    }

    private var rotuloStatus: String {
        switch model.charge.status {
        case .paid: "PAGA"
        case .overdue: "ATRASADA"
        case .canceled: "CANCELADA"
        default: "PENDENTE"
        }
    }

    private var corStatus: Color {
        switch model.charge.status {
        case .paid: Theme.success
        case .overdue: Theme.danger
        case .canceled: Theme.textSecondary
        default: Theme.warning
        }
    }

    private var dados: some View {
        ThemeCard(padding: 0) {
            VStack(spacing: 0) {
                linha("Descrição", model.charge.description)
                Divider().overlay(Theme.border)
                linha("Vencimento", PatientFormat.fullDate.string(from: model.charge.dueDate))
                if let m = model.charge.paymentMethodLabel {
                    Divider().overlay(Theme.border)
                    linha("Forma", m)
                }
                if let taxa = model.charge.splitFeeApplied, taxa > 0 {
                    Divider().overlay(Theme.border)
                    linha("Taxas (plataforma + Pix)", "− \(Formatters.brl(taxa))")
                    Divider().overlay(Theme.border)
                    linha(
                        "Você recebe",
                        Formatters.brl(model.charge.amount - taxa),
                        destaque: true
                    )
                }
                if let pago = model.charge.paidAt {
                    Divider().overlay(Theme.border)
                    linha("Pago em", PatientFormat.fullDate.string(from: pago))
                }
            }
        }
    }

    private func linha(_ rotulo: String, _ valor: String, destaque: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(rotulo)
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 12)
            Text(valor)
                .font(Theme.body(15, weight: destaque ? .semibold : .medium))
                .foregroundStyle(destaque ? Theme.success : Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private var acoes: some View {
        if store.isApproved {
            VStack(spacing: 8) {
                PrimaryButton(
                    title: model.charge.gatewayName == "ACOLHER"
                        ? "Ver Pix"
                        : "Cobrar por Pix (Acolher Financeiro)",
                    icon: "qrcode",
                    isLoading: model.isWorkingPix
                ) {
                    Task { await model.pixDoGateway() }
                }
                .accessibilityIdentifier("gwCobrarPix")
            }
        } else if store.overview != nil {
            // Só o Acolher Financeiro cobra. Sem conta aprovada, o caminho é
            // abrir a conta (não existe mais "recebida por fora").
            NavigationLink {
                FinGatewayHomeView()
            } label: {
                ThemeCard {
                    HStack(spacing: 12) {
                        Image(systemName: "building.columns")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 34, height: 34)
                            .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Para cobrar por Pix, abra sua conta no Acolher Financeiro")
                                .font(Theme.body(14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Leva cinco etapas, tudo dentro do app.")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    }
                }
            }
            .buttonStyle(.pressableSubtle)
        }

        if let link = model.linkAntigo {
            // Cobrança criada antes do gateway: o link do Asaas próprio ainda
            // vale pro paciente, então dá pra copiar. Discreto de propósito.
            Button {
                UIPasteboard.general.string = link
                Haptics.tap()
            } label: {
                Label("Copiar link antigo", systemImage: "doc.on.doc")
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.pressable)
        }
    }
}
