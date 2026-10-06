import Foundation
import Observation
import SwiftUI

// MARK: - Modelos (espelho de /zelo/conversa e /zelo/mensagens)

struct ZeloAnexo: Decodable, Hashable, Identifiable {
    let id: String
    let nome: String
    let mime: String
    let tamanho: Int
}

struct ZeloOpcao: Decodable, Hashable {
    let rotulo: String
    let detalhe: String?
}

struct ZeloAcao: Decodable, Hashable {
    /// "confirmar" = resumo esperando o "sim"; os outros tipos = feito.
    let tipo: String
    let titulo: String
    let detalhe: String?
    let link: String?

    var aguardandoConfirmacao: Bool { tipo == "confirmar" }
}

struct ZeloMensagem: Decodable, Identifiable, Hashable {
    let id: String
    let papel: String
    let texto: String
    let audio: Bool?
    let anexos: [ZeloAnexo]?
    let opcoes: [ZeloOpcao]?
    let acoes: [ZeloAcao]?
    let criadaEm: Date

    var daTerapeuta: Bool { papel == "terapeuta" }
}

private struct ZeloConversaResposta: Decodable {
    let ativo: Bool
    let audio: Bool
    let mensagens: [ZeloMensagem]
    let restantes: Int?
}

private struct ZeloEnvioResposta: Decodable {
    let mensagens: [ZeloMensagem]
    let restantes: Int?
}

/// Arquivo escolhido para mandar ao Zelo (ainda não enviado).
struct ZeloArquivoLocal: Identifiable, Hashable {
    let id = UUID()
    let data: Data
    let nome: String
    let mime: String
}

// MARK: - Estado

/// Chat do Zelo: uma conversa por terapeuta, guardada cifrada no servidor.
@MainActor
@Observable
final class ZeloStore {
    /// `var`: o logout troca por uma instância nova (ver SessionScope).
    static var shared = ZeloStore()

    var ativo = false
    var audioDisponivel = false
    var mensagens: [ZeloMensagem] = []
    var restantes: Int?
    var aberto = false
    var carregou = false
    var enviando = false
    var erro: String?
    /// Limite do plano: mostra o botão Gerenciar conta.
    var noLimite = false

    /// Altura ocupada embaixo por um botão flutuante da própria tela (ex.:
    /// "Criar cobrança" no Acolher Financeiro): o Zelo fica acima dele em vez
    /// de cobri-lo. A tela liga ao aparecer e zera ao sair.
    var folgaInferior: CGFloat = 0

    // Posição do botão flutuante (0…1 da área útil), salva entre aberturas.
    private let chaveX = "zelo.botao.x"
    private let chaveY = "zelo.botao.y"
    var posicao: CGPoint {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: chaveX) != nil else { return CGPoint(x: 1, y: 1) }
            return CGPoint(x: d.double(forKey: chaveX), y: d.double(forKey: chaveY))
        }
        set {
            UserDefaults.standard.set(newValue.x, forKey: chaveX)
            UserDefaults.standard.set(newValue.y, forKey: chaveY)
        }
    }

    /// Descobre se o Zelo está ligado (o botão some se não estiver).
    func carregarStatus() async {
        await carregar()
    }

    func carregar() async {
        do {
            let r: ZeloConversaResposta = try await APIClient.shared.get("zelo/conversa")
            ativo = r.ativo
            audioDisponivel = r.audio
            mensagens = r.mensagens
            restantes = r.restantes
            carregou = true
            erro = nil
        } catch {
            if !carregou { ativo = false }
            erro = (error as? APIError)?.message ?? "Sem conexão com o Zelo. Verifique a internet e tente de novo."
        }
    }

    /// Manda texto, áudio e/ou arquivos. Devolve true se a ação foi feita
    /// (para a tela tocar o haptic de sucesso).
    @discardableResult
    func enviar(texto: String, audio: (data: Data, mime: String)? = nil, arquivos: [ZeloArquivoLocal] = []) async -> Bool {
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty || audio != nil || !arquivos.isEmpty, !enviando else { return false }
        enviando = true
        erro = nil
        noLimite = false
        defer { enviando = false }
        var files: [(field: String, data: Data, fileName: String, mimeType: String)] = arquivos.map {
            (field: "arquivos", data: $0.data, fileName: $0.nome, mimeType: $0.mime)
        }
        if let audio {
            files.append((field: "audio", data: audio.data, fileName: "zelo-audio.m4a", mimeType: audio.mime))
        }
        do {
            let r: ZeloEnvioResposta = try await APIClient.shared.multipart(
                "zelo/mensagens",
                fields: limpo.isEmpty ? [:] : ["texto": limpo],
                files: files
            )
            mensagens.append(contentsOf: r.mensagens.filter { n in !mensagens.contains { $0.id == n.id } })
            restantes = r.restantes
            let feito = r.mensagens.last?.acoes?.contains { !$0.aguardandoConfirmacao } ?? false
            if feito { SessionScope.zeloFezAlgo() }
            return feito
        } catch let e as APIError {
            erro = e.message
            noLimite = e.code == "LIMITE_DO_PLANO"
            return false
        } catch {
            erro = "Sem conexão com o Zelo. Verifique a internet e tente de novo."
            return false
        }
    }

    func reiniciar() async -> Bool {
        do {
            let _: EmptyResponse = try await APIClient.shared.delete("zelo/conversa")
            mensagens = []
            erro = nil
            return true
        } catch {
            erro = "Não foi possível reiniciar agora."
            return false
        }
    }
}
