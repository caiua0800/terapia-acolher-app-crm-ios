import SwiftUI

// MARK: - Tela aberta pelo toque numa notificação
//
// Empilhada tanto pela lista do sininho quanto pelo push. Destinos que só
// precisam do id abrem direto; cobrança precisa do objeto inteiro e não há
// rota de uma cobrança só — busca a lista (do paciente ou das avulsas) e acha
// pelo id, como o "Ver cobrança" das automações. Não achou: cai na lista, sem
// erro feio.

struct NotifDestinationView: View {
    let destination: NotifDestination

    var body: some View {
        switch destination {
        case .supportChat(let ticketId):
            SupportChatView(ticketId: ticketId)
        case .automations:
            FinGatewayAutomacoesView()
        case .statement:
            FinGatewayLedgerView()
        case .allCharges:
            FinChargesEntryView()
        case .session(let id):
            AgendaSessionDetailView(sessionId: id)
        case .gatewayCharge(let patientId, let chargeId):
            NotifChargeResolverView(patientId: patientId, chargeId: chargeId)
        case .patientCharge(let patientId, let chargeId):
            NotifChargeResolverView(patientId: patientId, chargeId: chargeId)
        case .patientCharges(let patientId):
            NotifChargeResolverView(patientId: patientId, chargeId: nil)
        case .section, .external:
            // Não chegam aqui: trocam de seção ou abrem o navegador.
            EmptyView()
        }
    }
}

/// Acha a cobrança (ou o paciente) e mostra a tela certa no lugar do spinner.
private struct NotifChargeResolverView: View {
    let patientId: String?
    /// nil = cobranças do paciente (lembrete do mês).
    let chargeId: String?

    private enum Estado {
        case carregando
        case cobranca(FinCharge)
        case cobrancasDoPaciente(FinPatientRef)
        case todas
    }

    @State private var estado: Estado = .carregando

    var body: some View {
        Group {
            switch estado {
            case .carregando:
                ZStack {
                    Theme.background.ignoresSafeArea()
                    ProgressView().tint(Theme.primary)
                }
                .setToolbarTitle(chargeId == nil ? "Cobranças" : "Cobrança")
                .navigationBarTitleDisplayMode(.inline)
            case .cobranca(let charge):
                FinChargeDetailView(charge: charge) {}
            case .cobrancasDoPaciente(let patient):
                FinChargesView(patient: patient)
            case .todas:
                FinChargesEntryView()
            }
        }
        .task { await resolver() }
    }

    /// Paciente mínimo para a lista de cobranças dele.
    private struct PacienteMinimo: Decodable {
        let id: String
        let name: String
        let whatsapp: String?
        let whatsappEnabled: Bool?
    }

    @MainActor
    private func resolver() async {
        guard case .carregando = estado else { return }

        // Cobrança específica: a lista do paciente (ou das avulsas) traz o objeto.
        if let chargeId {
            let lista = try? await (patientId != nil
                ? FinanceAPI.charges(patientId: patientId)
                : FinanceAPI.charges(patientId: nil, kind: "STANDALONE"))
            if let charge = lista?.first(where: { $0.id == chargeId }) {
                estado = .cobranca(charge)
                return
            }
        }

        // Não achou (ou é o lembrete do mês): cobranças do paciente.
        if let patientId,
           let paciente: PacienteMinimo = try? await APIClient.shared.get("patients/\(patientId)") {
            estado = .cobrancasDoPaciente(FinPatientRef(
                id: paciente.id,
                name: paciente.name,
                whatsapp: paciente.whatsapp,
                whatsappEnabled: paciente.whatsappEnabled
            ))
            return
        }
        estado = .todas
    }
}
