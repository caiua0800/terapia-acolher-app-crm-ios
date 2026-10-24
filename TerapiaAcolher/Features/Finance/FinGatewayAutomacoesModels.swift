import Foundation
import SwiftUI

// MARK: - Cobrança automática do Acolher Financeiro (2026-10-23)
//
// Mesmo contrato do web (`web-app/lib/automacoes.ts`) e do backend
// (`src/modules/cobranca-automatica/`). Nos apps não há interruptor: a tela
// aparece sempre que a conta está aprovada (o web é que espera a aprovação
// das lojas pela flag `recurso.web.automacoesCobranca`).

enum AutFrequencia: String, Codable {
    case semanal = "WEEKLY"
    case mensal = "MONTHLY"
}

enum AutForma: String, Codable {
    case pix = "PIX"
    case cartao = "CARD"

    var rotulo: String { self == .cartao ? "Cartão" : "Pix" }
    var icone: String { self == .cartao ? "creditcard" : "qrcode" }
}

struct AutGrupo: Decodable, Hashable {
    let name: String
    let color: String?
}

struct AutPaciente: Decodable, Hashable {
    let id: String
    let name: String
    let group: AutGrupo?
    /// Só na lista de automações: paciente excluído pausa a automação.
    let deleted: Bool?
}

struct Automacao: Decodable, Identifiable, Hashable {
    let id: String
    let patient: AutPaciente
    let description: String
    let amount: Double
    let billingType: AutForma
    let passFees: Bool
    let frequency: AutFrequencia
    /// 0 = domingo … 6 = sábado.
    let weekday: Int?
    /// 1 a 28.
    let monthDay: Int?
    /// Mensal por dia útil: 1º a 10º (no lugar de monthDay).
    let businessDay: Int?
    /// "HH:mm"
    let sendTime: String
    /// Período da regra ("AAAA-MM-DD", inclusive); nil = sem limite.
    let startDate: String?
    let endDate: String?
    /// O período já terminou: não sai mais nada.
    let ended: Bool
    let dueInDays: Int
    let retryEnabled: Bool
    let retryAfterDays: Int
    let status: String // ACTIVE | PAUSED
    let pausedReason: String?
    /// "AAAA-MM-DD" da próxima cobrança (nil = pausada ou sem próxima).
    let nextDate: String?
    /// Instante ISO da próxima; texto mesmo, só serve para ordenar.
    let nextAt: String?
    let createdAt: String

    var pausada: Bool { status == "PAUSED" }

    var regra: AutRegra {
        AutRegra(
            frequencia: frequency,
            diaDaSemana: weekday,
            diaDoMes: monthDay,
            diaUtil: businessDay,
            hora: sendTime
        )
    }
}

/// Só o "quando" da automação — é sobre ele que os textos são montados.
struct AutRegra {
    var frequencia: AutFrequencia
    var diaDaSemana: Int?
    var diaDoMes: Int?
    var diaUtil: Int?
    var hora: String
}

/// Estado de uma data no calendário.
enum AutEstadoDaData: String, Decodable {
    case agendada = "AGENDADA"
    case cancelada = "CANCELADA"
    case pausada = "PAUSADA"
    case cobrada = "COBRADA"
    case falhou = "FALHOU"
    case naoEnviada = "NAO_ENVIADA"
}

struct AutCobrancaDaData: Decodable, Hashable {
    let id: String
    let status: String // PENDING | PAID | OVERDUE | CANCELED
    let paidAt: String?
    /// "AAAA-MM-DD"
    let dueDate: String
}

struct AutDataDaAutomacao: Decodable, Identifiable, Hashable {
    let automationId: String
    /// "AAAA-MM-DD" no fuso do terapeuta.
    let date: String
    /// Instante do envio (ISO).
    let at: String
    let patient: AutPaciente
    let billingType: AutForma
    let amount: Double
    /// Valor só desta data.
    let customAmount: Bool
    let state: AutEstadoDaData
    let failureReason: String?
    let charge: AutCobrancaDaData?
    let editable: Bool

    var id: String { automationId + date }
}

/// Criar e editar. Os campos da regra vão sempre com `null` explícito — no
/// PATCH, trocar de semanal para mensal precisa apagar o dia da semana.
struct AutPayload: Encodable {
    var patientId: String?
    var description: String
    var amount: Double
    var billingType: AutForma
    var passFees: Bool
    var frequency: AutFrequencia
    var weekday: Int?
    var monthDay: Int?
    var businessDay: Int?
    var sendTime: String
    var dueInDays: Int
    var retryEnabled: Bool
    var retryAfterDays: Int
    /// Editar: vale desta data em diante (as anteriores não mudam).
    var fromDate: String?

    enum CodingKeys: String, CodingKey {
        case patientId, description, amount, billingType, passFees, frequency
        case weekday, monthDay, businessDay, sendTime, dueInDays
        case retryEnabled, retryAfterDays, fromDate
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(patientId, forKey: .patientId)
        try c.encode(description, forKey: .description)
        try c.encode(amount, forKey: .amount)
        try c.encode(billingType, forKey: .billingType)
        try c.encode(passFees, forKey: .passFees)
        try c.encode(frequency, forKey: .frequency)
        try c.encode(weekday, forKey: .weekday)
        try c.encode(monthDay, forKey: .monthDay)
        try c.encode(businessDay, forKey: .businessDay)
        try c.encode(sendTime, forKey: .sendTime)
        try c.encode(dueInDays, forKey: .dueInDays)
        try c.encode(retryEnabled, forKey: .retryEnabled)
        try c.encode(retryAfterDays, forKey: .retryAfterDays)
        try c.encodeIfPresent(fromDate, forKey: .fromDate)
    }
}

/// Só uma data: cancelar, voltar a cobrar, outro valor ou voltar ao valor
/// normal (`amount: null` explícito).
private struct AutAlterarDataBody: Encodable {
    var canceled: Bool?
    /// `.some(nil)` manda `null` (volta ao valor da automação); `nil` não manda.
    var amount: Double??

    enum CodingKeys: String, CodingKey { case canceled, amount }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(canceled, forKey: .canceled)
        if let amount { try c.encode(amount, forKey: .amount) }
    }
}

// MARK: - Chamadas

enum AutomacoesAPI {
    static func lista() async throws -> [Automacao] {
        try await APIClient.shared.get("gateway/automations")
    }

    /// Intervalo de até 62 dias ("AAAA-MM-DD").
    static func calendario(de: String, ate: String) async throws -> [AutDataDaAutomacao] {
        try await APIClient.shared.get("gateway/automations/calendar", query: ["de": de, "ate": ate])
    }

    static func criar(_ payload: AutPayload) async throws -> Automacao {
        try await APIClient.shared.post("gateway/automations", body: payload)
    }

    static func alterar(id: String, _ payload: AutPayload) async throws -> Automacao {
        try await APIClient.shared.patch("gateway/automations/\(id)", body: payload)
    }

    static func pausar(id: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.post("gateway/automations/\(id)/pause")
    }

    static func retomar(id: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.post("gateway/automations/\(id)/resume")
    }

    static func excluir(id: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.delete("gateway/automations/\(id)")
    }

    static func cancelarData(id: String, dia: String, cancelada: Bool) async throws {
        let _: EmptyResponse = try await APIClient.shared.put(
            "gateway/automations/\(id)/dates/\(dia)",
            body: AutAlterarDataBody(canceled: cancelada)
        )
    }

    /// `valor: nil` volta ao valor da automação.
    static func valorDaData(id: String, dia: String, valor: Double?) async throws {
        let _: EmptyResponse = try await APIClient.shared.put(
            "gateway/automations/\(id)/dates/\(dia)",
            body: AutAlterarDataBody(amount: .some(valor))
        )
    }
}

// MARK: - Textos (os mesmos do web)

enum AutTexto {
    static let diasDaSemana = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]
    static let diasCurtos = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"]
    /// Prazos de vencimento oferecidos no formulário.
    static let prazos = [0, 1, 2, 3, 4, 5, 6, 7, 10, 15, 30]

    /// "Toda segunda às 09:00" / "Todo dia 5 às 09:00" / "Todo 5º dia útil às 09:00".
    static func quandoSai(_ r: AutRegra) -> String {
        if r.frequencia == .semanal {
            let indice = r.diaDaSemana ?? 0
            let dia = diasDaSemana[min(max(indice, 0), 6)]
            // "Todo domingo/sábado", "Toda segunda…sexta".
            let artigo = indice == 0 || indice == 6 ? "Todo" : "Toda"
            return "\(artigo) \(dia) às \(r.hora)"
        }
        if let util = r.diaUtil { return "Todo \(util)º dia útil às \(r.hora)" }
        return "Todo dia \(r.diaDoMes ?? 1) às \(r.hora)"
    }

    static func vencimento(_ dias: Int) -> String {
        if dias == 0 { return "vence no mesmo dia" }
        return dias == 1 ? "vence 1 dia depois" : "vence \(dias) dias depois"
    }

    static func reenvio(ligado: Bool, dias: Int) -> String {
        guard ligado else { return "sem reenvio" }
        return dias == 1
            ? "reenvia 1 dia depois do vencimento"
            : "reenvia \(dias) dias depois do vencimento"
    }

    /// "De 23/11 em diante" / "Até 22/11" / "" quando não há limite.
    static func periodo(_ a: Automacao) -> String {
        if let s = a.startDate, let e = a.endDate { return "De \(ddmm(s)) até \(ddmm(e))" }
        if let e = a.endDate { return "Até \(ddmm(e))" }
        if let s = a.startDate { return "De \(ddmm(s)) em diante" }
        return ""
    }

    /// "AAAA-MM-DD" → "26/10"
    static func ddmm(_ dia: String) -> String {
        guard dia.count >= 10 else { return dia }
        let partes = Array(dia)
        return "\(String(partes[8 ... 9]))/\(String(partes[5 ... 6]))"
    }

    static func maiuscula(_ texto: String) -> String {
        texto.prefix(1).uppercased() + texto.dropFirst()
    }

    static func primeiroNome(_ nome: String) -> String {
        nome.split(separator: " ").first.map(String.init) ?? nome
    }

    /// Busca sem acento e sem caixa.
    static func semAcento(_ texto: String) -> String {
        texto.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
    }
}

// MARK: - Datas no fuso do terapeuta

/// O calendário trabalha com dia-calendário ("AAAA-MM-DD") no fuso de São
/// Paulo, como o web — o celular do terapeuta pode estar em outro fuso.
enum AutDia {
    static let fuso = TimeZone(identifier: "America/Sao_Paulo") ?? .current

    static var calendario: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = fuso
        c.locale = Locale(identifier: "pt_BR")
        return c
    }

    static func iso(_ ano: Int, _ mes: Int, _ dia: Int) -> String {
        String(format: "%04d-%02d-%02d", ano, mes, dia)
    }

    static func hoje() -> String {
        let c = calendario.dateComponents([.year, .month, .day], from: Date())
        return iso(c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    /// (ano, mês 1–12, dia)
    static func partes(_ dia: String) -> (Int, Int, Int) {
        let p = dia.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return (2026, 1, 1) }
        return (p[0], p[1], p[2])
    }

    static func diasNoMes(_ ano: Int, _ mes: Int) -> Int {
        let data = calendario.date(from: DateComponents(year: ano, month: mes, day: 1)) ?? Date()
        return calendario.range(of: .day, in: .month, for: data)?.count ?? 30
    }

    /// 0 = domingo … 6 = sábado.
    static func diaDaSemana(_ ano: Int, _ mes: Int, _ dia: Int) -> Int {
        let data = calendario.date(from: DateComponents(year: ano, month: mes, day: dia)) ?? Date()
        return calendario.component(.weekday, from: data) - 1
    }

    /// "Sexta-feira, 23 de outubro"
    static func titulo(_ dia: String) -> String {
        let (a, m, d) = partes(dia)
        let data = calendario.date(from: DateComponents(year: a, month: m, day: d, hour: 12)) ?? Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.timeZone = fuso
        f.dateFormat = "EEEE, d 'de' MMMM"
        return AutTexto.maiuscula(f.string(from: data))
    }

    /// "Outubro de 2026"
    static func mesAno(_ ano: Int, _ mes: Int) -> String {
        let data = calendario.date(from: DateComponents(year: ano, month: mes, day: 1, hour: 12)) ?? Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.timeZone = fuso
        f.dateFormat = "MMMM 'de' yyyy"
        return AutTexto.maiuscula(f.string(from: data))
    }

    /// Próxima data da regra a partir de hoje ("AAAA-MM-DD"). Só para os
    /// exemplos do formulário: quem decide a data de verdade é o servidor (a
    /// hora de hoje já ter passado não entra na conta).
    static func proximaData(_ r: AutRegra) -> String {
        let hoje = hoje()
        let (a, m, d) = partes(hoje)
        if r.frequencia == .semanal {
            let atual = diaDaSemana(a, m, d)
            let faltam = ((r.diaDaSemana ?? 1) - atual + 7) % 7
            let base = calendario.date(from: DateComponents(year: a, month: m, day: d, hour: 12)) ?? Date()
            let alvo = calendario.date(byAdding: .day, value: faltam, to: base) ?? base
            let c = calendario.dateComponents([.year, .month, .day], from: alvo)
            return iso(c.year ?? a, c.month ?? m, c.day ?? d)
        }
        func doMes(_ ano: Int, _ mes: Int) -> String {
            if let util = r.diaUtil { return AutDiaUtil.enesimo(ano: ano, mes: mes, n: util) }
            return iso(ano, mes, r.diaDoMes ?? 1)
        }
        let nesteMes = doMes(a, m)
        if nesteMes >= hoje { return nesteMes }
        return m == 12 ? doMes(a + 1, 1) : doMes(a, m + 1)
    }

    /// "seg", "ter"…
    static func semanaCurta(_ dia: String) -> String {
        let (a, m, d) = partes(dia)
        return ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"][diaDaSemana(a, m, d)]
    }

    private static let instante: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let instanteSemFracao = ISO8601DateFormatter()

    static func data(deInstante texto: String) -> Date? {
        instante.date(from: texto) ?? instanteSemFracao.date(from: texto)
    }

    /// "09:00" do instante ISO, no fuso de São Paulo.
    static func hora(deInstante texto: String) -> String {
        guard let data = data(deInstante: texto) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.timeZone = fuso
        f.dateFormat = "HH:mm"
        return f.string(from: data)
    }

    /// "23/10/2026" do instante ISO.
    static func diaCompleto(deInstante texto: String) -> String {
        guard let data = data(deInstante: texto) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.timeZone = fuso
        f.dateFormat = "dd/MM/yyyy"
        return f.string(from: data)
    }
}

// MARK: - Dia útil
//
// Segunda a sexta fora de feriado nacional. Mesma conta do backend
// (agenda-da-automacao.ts) e do web (`enesimoDiaUtil`), só pra mostrar as
// próximas datas no formulário.

enum AutDiaUtil {
    private static let fixos: Set<String> = [
        "01-01", "04-21", "05-01", "09-07", "10-12", "11-02", "11-15", "11-20", "12-25",
    ]

    /// Domingo de Páscoa (algoritmo de Meeus/Butcher, o mesmo do backend).
    private static func pascoa(_ ano: Int) -> (Int, Int) {
        let a = ano % 19
        let b = ano / 100
        let c = ano % 100
        let h = (19 * a + b - b / 4 - (b - (b + 8) / 25 + 1) / 3 + 15) % 30
        let l = (32 + 2 * (b % 4) + 2 * (c / 4) - h - (c % 4)) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let n = h + l - 7 * m + 114
        return (n / 31, (n % 31) + 1)
    }

    private static func ehDiaUtil(_ ano: Int, _ mes: Int, _ dia: Int) -> Bool {
        let semana = AutDia.diaDaSemana(ano, mes, dia)
        if semana == 0 || semana == 6 { return false }
        if fixos.contains(String(format: "%02d-%02d", mes, dia)) { return false }
        // Sexta-feira Santa: dois dias antes da Páscoa.
        let (mp, dp) = pascoa(ano)
        let cal = AutDia.calendario
        guard let domingo = cal.date(from: DateComponents(year: ano, month: mp, day: dp, hour: 12)),
              let santa = cal.date(byAdding: .day, value: -2, to: domingo)
        else { return true }
        let s = cal.dateComponents([.month, .day], from: santa)
        return !(s.month == mes && s.day == dia)
    }

    /// O N-ésimo dia útil de um mês ("AAAA-MM-DD"); mês de 1 a 12.
    static func enesimo(ano: Int, mes: Int, n: Int) -> String {
        var contados = 0
        for dia in 1 ... AutDia.diasNoMes(ano, mes) where ehDiaUtil(ano, mes, dia) {
            contados += 1
            if contados == n { return AutDia.iso(ano, mes, dia) }
        }
        return AutDia.iso(ano, mes, AutDia.diasNoMes(ano, mes))
    }

    /// "09/11, 07/12 e 08/01": as três próximas datas do Nº dia útil.
    static func proximas(_ n: Int) -> String {
        let hoje = AutDia.hoje()
        var (ano, mes, _) = AutDia.partes(hoje)
        var datas: [String] = []
        while datas.count < 3 {
            let dia = enesimo(ano: ano, mes: mes, n: n)
            if dia >= hoje { datas.append(AutTexto.ddmm(dia)) }
            mes += 1
            if mes > 12 { mes = 1; ano += 1 }
        }
        return "\(datas[0]), \(datas[1]) e \(datas[2])"
    }
}

// MARK: - Aparência de cada data no calendário

struct AutAparencia {
    let rotulo: String
    let cor: Color
    let fundo: Color
}

/// Azul do "online" (Agendada): os mesmos hex do web (`--color-online`) e do
/// selo Online da Agenda, que ainda não moravam no tema.
extension Theme {
    static let online = Color(hex: 0x3E637F)
    static let onlineSoft = Color(hex: 0xDDEAF3)
}

extension AutDataDaAutomacao {
    var aparencia: AutAparencia {
        let cinza = AutAparencia(rotulo: "", cor: Theme.textSecondary, fundo: Theme.border.opacity(0.7))
        if state == .cobrada, let charge {
            switch charge.status {
            case "PAID": return AutAparencia(rotulo: "PAGA", cor: Theme.success, fundo: Theme.successSoft)
            case "OVERDUE": return AutAparencia(rotulo: "ATRASADA", cor: Theme.danger, fundo: Theme.dangerSoft)
            case "CANCELED": return AutAparencia(rotulo: "CANCELADA", cor: cinza.cor, fundo: cinza.fundo)
            default: return AutAparencia(rotulo: "ENVIADA", cor: Theme.warning, fundo: Theme.warningSoft)
            }
        }
        switch state {
        case .cancelada: return AutAparencia(rotulo: "NÃO VAI SAIR", cor: cinza.cor, fundo: cinza.fundo)
        case .pausada: return AutAparencia(rotulo: "PAUSADA", cor: cinza.cor, fundo: cinza.fundo)
        case .falhou, .naoEnviada: return AutAparencia(rotulo: "NÃO SAIU", cor: Theme.danger, fundo: Theme.dangerSoft)
        default: return AutAparencia(rotulo: "AGENDADA", cor: Theme.online, fundo: Theme.onlineSoft)
        }
    }

    /// Cancelada nesta data ou cobrança cancelada: aparece riscada.
    var riscada: Bool { state == .cancelada || charge?.status == "CANCELED" }
}
