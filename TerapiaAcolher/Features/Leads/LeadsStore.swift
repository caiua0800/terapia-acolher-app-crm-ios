import Foundation
import Observation

/// Cliente dos leads. Os leads vêm do sistema de leads da Terapia Acolher, via
/// CRM, em nome do terapeuta (mesmo aperto de mão da Vitrine: ele confirma no
/// portal e volta, sem copiar chave). O que é do CRM é o status do funil e o
/// paciente em que o lead virou.
///
/// Instância única de propósito: lista, ficha e Início precisam ver a mesma
/// mudança de status na hora, e o estado sobrevive à navegação — voltar para a
/// tela não dá spinner de novo, só atualiza por baixo.
@Observable
final class LeadsStore {
    static let shared = LeadsStore()

    private(set) var leads: [Lead] = []
    /// `nil` até a primeira consulta responder.
    private(set) var connection: LeadsConnectionStatus?
    var isLoading = true
    var errorMessage: String?
    var isWorking = false
    var alerta: String?
    var showAlerta = false

    var isConnected: Bool { connection?.connected == true }

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

    // MARK: Carga

    @MainActor
    func load() async {
        isLoading = connection == nil
        errorMessage = nil
        do {
            let status = try await LeadsAPI.status()
            connection = status
            if status.connected {
                leads = try await LeadsAPI.list()
            } else {
                leads = []
            }
        } catch is CancellationError {
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar seus leads."
        }
        isLoading = false
    }

    // MARK: Conexão

    @MainActor
    func connectURL() async -> URL? {
        isWorking = true
        defer { isWorking = false }
        do {
            return try await LeadsAPI.connectUrl()
        } catch let error as APIError {
            present(error.message)
        } catch {
            present("Não foi possível abrir a conexão com o sistema de leads.")
        }
        return nil
    }

    @MainActor
    func disconnect() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await LeadsAPI.disconnect()
            leads = []
            connection = try await LeadsAPI.status()
            Haptics.success()
        } catch let error as APIError {
            present(error.message)
        } catch {
            present("Não foi possível desconectar.")
        }
    }

    // MARK: Mutações (otimistas: a tela muda na hora, a API confirma por baixo)

    @MainActor
    func updateStatus(_ id: String, to status: LeadStatus) async {
        guard let i = leads.firstIndex(where: { $0.id == id }) else { return }
        let anterior = leads[i].status
        guard anterior != status else { return }
        leads[i].status = status
        do {
            try await LeadsAPI.updateStatus(id, to: status)
        } catch {
            if let j = leads.firstIndex(where: { $0.id == id }) { leads[j].status = anterior }
            present((error as? APIError)?.message ?? "Não foi possível salvar o status.")
        }
    }

    @MainActor
    func markConverted(_ id: String, patientId: String) async {
        guard let i = leads.firstIndex(where: { $0.id == id }) else { return }
        let anterior = leads[i]
        leads[i].convertedPatientId = patientId
        leads[i].status = .agendado
        do {
            try await LeadsAPI.linkPatient(id, patientId: patientId)
        } catch {
            // A ficha do paciente já existe; o que falhou foi só a marcação.
            if let j = leads.firstIndex(where: { $0.id == id }) { leads[j] = anterior }
            present((error as? APIError)?.message ?? "O paciente foi criado, mas não deu para marcar o lead como convertido.")
        }
    }

    @MainActor
    private func present(_ mensagem: String) {
        alerta = mensagem
        showAlerta = true
    }
}
