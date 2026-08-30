import Foundation
import Observation

/// Base de leads **em memória** para a demonstração. Nada persiste, nada sai do
/// aparelho — ver o aviso em LeadsModels.swift.
///
/// Singleton de propósito: lista, detalhe e dashboard precisam ver a mesma
/// mudança de status na hora. Quando existir backend, esta classe vira o
/// cliente da API e as telas não mudam.
@Observable
final class LeadsStore {
    static let shared = LeadsStore()

    private(set) var leads: [Lead] = LeadsStore.seed()

    // MARK: Consultas

    var openCount: Int { leads.filter { $0.status.isOpen }.count }
    var uncontactedCount: Int { leads.filter { $0.status == .novo }.count }
    var lateCount: Int { leads.filter { $0.sla == .late }.count }
    var convertedCount: Int { leads.filter { $0.status == .agendado }.count }

    /// Taxa de conversão sobre os leads já decididos (agendou ou não converteu).
    /// Contar os que ainda estão em aberto no denominador puniria o terapeuta
    /// por leads que chegaram hoje.
    var conversionRate: Int? {
        let decided = leads.filter { !$0.status.isOpen }
        guard !decided.isEmpty else { return nil }
        return Int((Double(convertedCount) / Double(decided.count) * 100).rounded())
    }

    func lead(id: String) -> Lead? { leads.first { $0.id == id } }

    // MARK: Mutações

    func updateStatus(_ id: String, to status: LeadStatus) {
        guard let i = leads.firstIndex(where: { $0.id == id }) else { return }
        leads[i].status = status
    }

    func markConverted(_ id: String, patientId: String) {
        guard let i = leads.firstIndex(where: { $0.id == id }) else { return }
        leads[i].convertedPatientId = patientId
        leads[i].status = .agendado
    }

    // MARK: Semente

    private static func seed() -> [Lead] {
        func horasAtras(_ h: Double) -> Date { Date().addingTimeInterval(-h * 3600) }

        return [
            Lead(
                id: "l1", status: .novo, receivedAt: horasAtras(0.4),
                name: "Mariana Ferreira", whatsapp: "+55 41 98812-4470",
                gender: .feminino, preferredTherapistGender: "feminino",
                shift: .noite, reason: "Ansiedade e crises de pânico no trabalho",
                therapyFor: .normal, contactWhen: "Hoje depois das 19h",
                childName: nil, childAge: nil, relativeName: nil, relativeContact: nil
            ),
            Lead(
                id: "l2", status: .novo, receivedAt: horasAtras(9),
                name: "Rodrigo Salles", whatsapp: "+55 11 97744-1180",
                gender: .masculino, preferredTherapistGender: "indiferente",
                shift: .manha, reason: "Luto pela perda do pai, não consigo retomar a rotina",
                therapyFor: .normal, contactWhen: "De manhã, antes das 10h",
                childName: nil, childAge: nil, relativeName: nil, relativeContact: nil
            ),
            Lead(
                id: "l3", status: .novo, receivedAt: horasAtras(52),
                name: "Camila Duarte", whatsapp: "+55 21 99120-3355",
                gender: .feminino, preferredTherapistGender: "feminino",
                shift: .tarde, reason: "Meu filho de 8 anos está muito agressivo na escola",
                therapyFor: .infantil, contactWhen: "Qualquer horário à tarde",
                childName: "Théo Duarte", childAge: "8", relativeName: nil, relativeContact: nil
            ),
            Lead(
                id: "l4", status: .tentandoContato, receivedAt: horasAtras(26),
                name: "Ana e Paulo Menezes", whatsapp: "+55 47 98301-7712",
                gender: .feminino, preferredTherapistGender: "indiferente",
                shift: .noite, reason: "Estamos brigando muito desde que o bebê nasceu",
                therapyFor: .casal, contactWhen: "Depois das 20h, os dois juntos",
                childName: nil, childAge: nil, relativeName: nil, relativeContact: nil
            ),
            Lead(
                id: "l5", status: .tentandoContato, receivedAt: horasAtras(70),
                name: "Juliana Prado", whatsapp: "+55 31 98866-2109",
                gender: .feminino, preferredTherapistGender: "feminino",
                shift: .qualquer, reason: "Burnout — afastada do trabalho há dois meses",
                therapyFor: .normal, contactWhen: "Pode ligar a hora que for",
                childName: nil, childAge: nil, relativeName: nil, relativeContact: nil
            ),
            Lead(
                id: "l6", status: .negociando, receivedAt: horasAtras(96),
                name: "Beatriz Nunes", whatsapp: "+55 85 99433-8890",
                gender: .feminino, preferredTherapistGender: "feminino",
                shift: .tarde, reason: "Quero terapia para minha mãe, ela está muito isolada",
                therapyFor: .outraPessoa, contactWhen: "Falar comigo primeiro, não com ela",
                childName: nil, childAge: nil,
                relativeName: "Dona Célia Nunes", relativeContact: "+55 85 99120-4432"
            ),
            Lead(
                id: "l7", status: .negociando, receivedAt: horasAtras(120),
                name: "Fernando Kubitschek", whatsapp: "+55 61 98177-6654",
                gender: .masculino, preferredTherapistGender: "masculino",
                shift: .noite, reason: "Dificuldade em manter relacionamentos",
                therapyFor: .normal, contactWhen: "Fim de tarde",
                childName: nil, childAge: nil, relativeName: nil, relativeContact: nil
            ),
            Lead(
                id: "l8", status: .agendado, receivedAt: horasAtras(168),
                name: "Larissa Antunes", whatsapp: "+55 51 99008-2245",
                gender: .feminino, preferredTherapistGender: "indiferente",
                shift: .manha, reason: "Autoconhecimento, primeira vez em terapia",
                therapyFor: .normal, contactWhen: "Manhã de qualquer dia",
                childName: nil, childAge: nil, relativeName: nil, relativeContact: nil,
                convertedPatientId: "demo-paciente-1"
            ),
            Lead(
                id: "l9", status: .agendado, receivedAt: horasAtras(240),
                name: "Otávio Belmonte", whatsapp: "+55 62 98455-1123",
                gender: .masculino, preferredTherapistGender: "indiferente",
                shift: .tarde, reason: "Ansiedade antes de apresentações",
                therapyFor: .normal, contactWhen: "Depois do almoço",
                childName: nil, childAge: nil, relativeName: nil, relativeContact: nil,
                convertedPatientId: "demo-paciente-2"
            ),
            Lead(
                id: "l11", status: .novo, receivedAt: horasAtras(0.25),
                name: "Thiago Marchetti", whatsapp: "+55 48 99655-7781",
                gender: .masculino, preferredTherapistGender: "masculino",
                shift: .noite, reason: "Insônia e pensamentos acelerados há meses",
                therapyFor: .normal, contactWhen: "Depois das 21h, quando as crianças dormem",
                childName: nil, childAge: nil, relativeName: nil, relativeContact: nil
            ),
            Lead(
                id: "l12", status: .novo, receivedAt: horasAtras(31),
                name: "Renata Aguiar", whatsapp: "+55 27 98209-4416",
                gender: .feminino, preferredTherapistGender: "feminino",
                shift: .manha, reason: "Minha filha de 14 anos parou de sair de casa",
                therapyFor: .infantil, contactWhen: "Manhã, antes do trabalho",
                childName: "Sofia Aguiar", childAge: "14", relativeName: nil, relativeContact: nil
            ),
            Lead(
                id: "l10", status: .naoConverteu, receivedAt: horasAtras(300),
                name: "Patrícia Vasques", whatsapp: "+55 19 99712-3308",
                gender: .feminino, preferredTherapistGender: "feminino",
                shift: .noite, reason: "Procurando terapia de casal",
                therapyFor: .casal, contactWhen: "À noite",
                childName: nil, childAge: nil, relativeName: nil, relativeContact: nil
            ),
        ]
    }
}
