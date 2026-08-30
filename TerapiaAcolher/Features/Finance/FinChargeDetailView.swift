import Observation
import SwiftUI

@Observable
@MainActor
final class FinChargeDetailModel {
    var charge: FinCharge
    var metodos: [FinFees.Method] = []
    var isWorking = false
    var alerta: String?
    var showAlerta = false
    var checkout: FinCheckoutResult?

    init(charge: FinCharge) {
        self.charge = charge
    }

    var temLink: Bool { (charge.gatewayInvoiceUrl?.isEmpty == false) }
    var emAberto: Bool { charge.status == .pending || charge.status == .overdue }

    func carregar() async {
        // Quais métodos existem HOJE vem do servidor: quando o cartão foi
        // liberado, os apps já publicados passaram a oferecer sem release novo.
        if let f = try? await FinanceAPI.fees() {
            metodos = f.methods.filter(\.available)
        }
        if let atual = try? await FinanceAPI.charges(patientId: charge.patientId)
            .first(where: { $0.id == charge.id }) {
            charge = atual
        }
    }

    func gerarLink(_ metodoId: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            checkout = try await FinanceAPI.checkout(id: charge.id, billingType: metodoId)
            Haptics.success()
            await carregar()
        } catch let error as APIError {
            present(error.message)
        } catch {
            present("Não foi possível gerar o link. Verifique sua conexão.")
        }
    }

    func marcarPaga() async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await FinanceAPI.payCharge(id: charge.id)
            Haptics.success()
            await carregar()
        } catch let error as APIError {
            present(error.message)
        } catch {
            present("Não foi possível marcar como paga.")
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
                }
                .padding(Theme.screenPadding)
                .padding(.bottom, 32)
            }
        }
        .setToolbarTitle("Cobrança")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.carregar() }
        .refreshable { await model.carregar() }
        .alert("Ops", isPresented: $model.showAlerta) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alerta ?? "Algo deu errado.")
        }
        .sheet(item: $model.checkout) { resultado in
            FinChargeLinkSheet(
                result: resultado,
                patientName: model.charge.patient?.name ?? "seu paciente"
            ) {
                model.checkout = nil
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

            StatusBadge(
                label: rotuloStatus,
                color: corStatus,
                background: corStatus.opacity(0.14)
            )

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
                    linha("Taxa do sistema", "− \(Formatters.brl(taxa))")
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
        if model.temLink, let urlString = model.charge.gatewayInvoiceUrl {
            // Link já existe: o que ele quer é COPIAR e mandar.
            PrimaryButton(title: "Ver link e copiar mensagem", icon: "text.bubble") {
                model.checkout = FinCheckoutResult(
                    id: model.charge.id,
                    status: model.charge.status,
                    amount: model.charge.amount,
                    splitFeeApplied: model.charge.splitFeeApplied,
                    invoiceUrl: urlString,
                    pixQrCode: nil,
                    pixQrCodeImage: nil
                )
            }
        } else {
            // Sem link ainda: oferece os métodos que o SERVIDOR diz existirem —
            // antes daqui saía só "Cobrar via Pix", cravado, mesmo depois de o
            // cartão ter sido liberado.
            VStack(spacing: 10) {
                ForEach(model.metodos) { metodo in
                    Button {
                        Task { await model.gerarLink(metodo.id) }
                    } label: {
                        HStack(spacing: 10) {
                            if model.isWorking {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Image(systemName: metodo.id == "PIX" ? "qrcode" : "creditcard")
                            }
                            Text("Cobrar via \(metodo.label)")
                                .font(Theme.body(16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.pressable)
                    .disabled(model.isWorking)
                }
            }
        }

        Button {
            Task {
                await model.marcarPaga()
                onChange()
            }
        } label: {
            Label("Marcar como paga", systemImage: "checkmark.circle")
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(Theme.success)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Theme.successSoft, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.pressable)
        .disabled(model.isWorking)
    }
}
