import Foundation

/// "Meu Zelo AI" (2026-10-06): quem é o Zelo (gênero, personalidade, jeito de
/// falar) e o "Bom dia do Zelo". Contrato: `GET/PUT zelo/config` e
/// `GET zelo/bom-dia/previa`. Só chaves de listas fixas vindas do servidor —
/// nada de texto livre (o servidor traduz cada chave numa instrução dele).

struct ZeloTraco: Codable, Hashable, Identifiable {
    let chave: String
    let rotulo: String
    var id: String { chave }
}

struct ZeloItensBomDia: Codable, Equatable {
    var agenda: Bool = false
    var sessoes: Bool = true
    var saldo: Bool = false
    var aReceberMes: Bool = false
    var leadsPendentes: Bool = false
    var vitrineVisualizacoes: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agenda = try c.decodeIfPresent(Bool.self, forKey: .agenda) ?? false
        sessoes = try c.decodeIfPresent(Bool.self, forKey: .sessoes) ?? false
        saldo = try c.decodeIfPresent(Bool.self, forKey: .saldo) ?? false
        aReceberMes = try c.decodeIfPresent(Bool.self, forKey: .aReceberMes) ?? false
        leadsPendentes = try c.decodeIfPresent(Bool.self, forKey: .leadsPendentes) ?? false
        vitrineVisualizacoes = try c.decodeIfPresent(Bool.self, forKey: .vitrineVisualizacoes) ?? false
    }
}

/// Onde o bom dia chega (2026-10-06): e-mail já funciona; WhatsApp "em breve".
struct ZeloCanais: Codable, Equatable {
    var email: Bool = true
    var whatsapp: Bool = false

    init(email: Bool = true, whatsapp: Bool = false) {
        self.email = email
        self.whatsapp = whatsapp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        email = try c.decodeIfPresent(Bool.self, forKey: .email) ?? true
        whatsapp = try c.decodeIfPresent(Bool.self, forKey: .whatsapp) ?? false
    }
}

struct ZeloBomDia: Codable, Equatable {
    var ativo: Bool = false
    /// "HH:mm" no fuso do terapeuta.
    var horario: String = "07:00"
    /// 0 = domingo … 6 = sábado.
    var dias: [Int] = [1, 2, 3, 4, 5]
    var itens = ZeloItensBomDia()
    /// Backend antigo não manda: e-mail ligado por padrão.
    var canais = ZeloCanais()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ativo = try c.decodeIfPresent(Bool.self, forKey: .ativo) ?? false
        horario = try c.decodeIfPresent(String.self, forKey: .horario) ?? "07:00"
        dias = try c.decodeIfPresent([Int].self, forKey: .dias) ?? [1, 2, 3, 4, 5]
        itens = try c.decodeIfPresent(ZeloItensBomDia.self, forKey: .itens) ?? ZeloItensBomDia()
        canais = try c.decodeIfPresent(ZeloCanais.self, forKey: .canais) ?? ZeloCanais()
    }
}

struct ZeloDisponiveis: Codable, Equatable {
    var agenda: Bool = false
    var sessoes: Bool = true
    var saldo: Bool = false
    var aReceberMes: Bool = true
    var leadsPendentes: Bool = false
    var vitrineVisualizacoes: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agenda = try c.decodeIfPresent(Bool.self, forKey: .agenda) ?? false
        sessoes = try c.decodeIfPresent(Bool.self, forKey: .sessoes) ?? true
        saldo = try c.decodeIfPresent(Bool.self, forKey: .saldo) ?? false
        aReceberMes = try c.decodeIfPresent(Bool.self, forKey: .aReceberMes) ?? true
        leadsPendentes = try c.decodeIfPresent(Bool.self, forKey: .leadsPendentes) ?? false
        vitrineVisualizacoes = try c.decodeIfPresent(Bool.self, forKey: .vitrineVisualizacoes) ?? false
    }
}

struct ZeloOpcoes: Codable, Equatable {
    var personalidade: [ZeloTraco] = []
    var jeitoDeFalar: [ZeloTraco] = []
    /// Pares que se excluem (ex.: mais formal × mais informal).
    var conflitos: [[String]] = []
}

struct ZeloLimites: Codable, Equatable {
    var personalidade: Int = 5
    var jeitoDeFalar: Int = 5
}

struct ZeloConfig: Codable, Equatable {
    var genero: String = "M"
    var personalidade: [String] = []
    var jeitoDeFalar: [String] = []
    var bomDia = ZeloBomDia()
    var disponiveis = ZeloDisponiveis()
    var opcoes = ZeloOpcoes()
    var limites = ZeloLimites()
    var canalDisponivel: Bool = false
    /// Quais canais o servidor consegue usar agora (WhatsApp só com o número do Zelo no ar).
    var canaisDisponiveis = ZeloCanais(email: true, whatsapp: false)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        genero = try c.decodeIfPresent(String.self, forKey: .genero) ?? "M"
        personalidade = try c.decodeIfPresent([String].self, forKey: .personalidade) ?? []
        jeitoDeFalar = try c.decodeIfPresent([String].self, forKey: .jeitoDeFalar) ?? []
        bomDia = try c.decodeIfPresent(ZeloBomDia.self, forKey: .bomDia) ?? ZeloBomDia()
        disponiveis = try c.decodeIfPresent(ZeloDisponiveis.self, forKey: .disponiveis) ?? ZeloDisponiveis()
        opcoes = try c.decodeIfPresent(ZeloOpcoes.self, forKey: .opcoes) ?? ZeloOpcoes()
        limites = try c.decodeIfPresent(ZeloLimites.self, forKey: .limites) ?? ZeloLimites()
        canalDisponivel = try c.decodeIfPresent(Bool.self, forKey: .canalDisponivel) ?? false
        canaisDisponiveis = try c.decodeIfPresent(ZeloCanais.self, forKey: .canaisDisponiveis)
            ?? ZeloCanais(email: true, whatsapp: canalDisponivel)
    }
}

/// O que vai no PUT: só o que o terapeuta escolhe (o resto é do servidor).
struct ZeloConfigEnvio: Encodable {
    let genero: String
    let personalidade: [String]
    let jeitoDeFalar: [String]
    let bomDia: ZeloBomDia
}

struct ZeloBomDiaPrevia: Codable {
    let texto: String
    let geradoEm: String?
}
