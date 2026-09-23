import QuickLook
import SwiftUI

// MARK: - PDF da transcrição e do resumo
//
// Pedido do Caiuã (2026-09-23), igual ao CRM web: baixar a transcrição e o
// resumo da sessão em PDF. O servidor monta o documento na hora (uma hora de
// conversa leva menos de um segundo) e nada fica guardado lá — por isso é um
// download direto com carregando no controle tocado, não uma fila.
//
// No aparelho, o PDF abre no Quick Look (visualizar + compartilhar/salvar, tudo
// nativo). É dado sensível de saúde: o arquivo fica numa pasta temporária
// própria, com proteção de arquivo completa, e é apagado quando o Quick Look fecha.

enum TranscriptPDFKind: String {
    case transcricao
    case resumo

    func path(sessionId: String, transcriptId: String) -> String {
        switch self {
        case .transcricao: "sessions/\(sessionId)/transcricao/\(transcriptId)/pdf"
        case .resumo: "sessions/\(sessionId)/transcricao/\(transcriptId)/resumo/pdf"
        }
    }

    var fallbackName: String { "\(rawValue).pdf" }
}

@MainActor
@Observable
final class TranscriptPDFDownloader {
    /// Qual PDF está sendo gerado — o spinner fica no controle tocado.
    private(set) var baixando: TranscriptPDFKind? = nil
    /// Arquivo aberto no Quick Look. Voltar a nil apaga o arquivo.
    var arquivo: URL? = nil {
        didSet {
            if let antigo = oldValue, antigo != arquivo { Self.apagar(antigo) }
        }
    }
    var erro: String? = nil

    func baixar(_ kind: TranscriptPDFKind, sessionId: String, transcriptId: String) async {
        guard baixando == nil else { return }
        Haptics.tap()
        baixando = kind
        defer { baixando = nil }
        do {
            let baixado = try await APIClient.shared.download(
                kind.path(sessionId: sessionId, transcriptId: transcriptId),
                fallbackName: kind.fallbackName
            )
            let pasta = FileManager.default.temporaryDirectory
                .appendingPathComponent("pdf-sessao-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
            let nome = baixado.fileName.replacingOccurrences(of: "/", with: "-")
            let destino = pasta.appendingPathComponent(nome.isEmpty ? kind.fallbackName : nome)
            try baixado.data.write(to: destino, options: [.atomic, .completeFileProtection])
            Haptics.success()
            arquivo = destino
        } catch let error as APIError {
            erro = error.message
        } catch {
            erro = "Não foi possível gerar o PDF. Tente de novo."
        }
    }

    /// Apaga a pasta temporária inteira (o arquivo mora sozinho nela).
    private static func apagar(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

extension View {
    /// Quick Look do PDF baixado + aviso de erro. O arquivo some ao fechar.
    func transcriptPDFPreview(_ downloader: TranscriptPDFDownloader) -> some View {
        self
            .quickLookPreview(Binding(
                get: { downloader.arquivo },
                set: { downloader.arquivo = $0 }
            ))
            .alert("Não foi possível gerar o PDF", isPresented: Binding(
                get: { downloader.erro != nil },
                set: { if !$0 { downloader.erro = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(downloader.erro ?? "")
            }
    }
}

// MARK: - Botões

/// "Baixar PDF" com carregando no próprio botão.
struct TranscriptPDFButton: View {
    let kind: TranscriptPDFKind
    let sessionId: String
    let transcriptId: String
    var title: String = "Baixar PDF"

    @State private var downloader = TranscriptPDFDownloader()

    var body: some View {
        Button {
            Task { await downloader.baixar(kind, sessionId: sessionId, transcriptId: transcriptId) }
        } label: {
            HStack(spacing: 7) {
                if downloader.baixando != nil {
                    ProgressView().controlSize(.small).tint(Theme.primary)
                } else {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(Theme.body(13.5, weight: .semibold))
            }
            .foregroundStyle(Theme.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .disabled(downloader.baixando != nil)
        .accessibilityLabel(title)
        .transcriptPDFPreview(downloader)
    }
}

/// Ícone da barra da folha: baixa e abre o PDF.
struct TranscriptPDFToolbarButton: View {
    let kind: TranscriptPDFKind
    let sessionId: String
    let transcriptId: String

    @State private var downloader = TranscriptPDFDownloader()

    var body: some View {
        Button {
            Task { await downloader.baixar(kind, sessionId: sessionId, transcriptId: transcriptId) }
        } label: {
            if downloader.baixando != nil {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.down.doc")
            }
        }
        .disabled(downloader.baixando != nil)
        .accessibilityLabel(kind == .resumo ? "Baixar resumo em PDF" : "Baixar transcrição em PDF")
        .transcriptPDFPreview(downloader)
    }
}

/// Menu do cartão da lista: transcrição sempre; resumo quando já existe.
struct TranscriptPDFMenu: View {
    let sessionId: String
    let transcriptId: String
    let resumoPronto: Bool

    @State private var downloader = TranscriptPDFDownloader()

    var body: some View {
        Menu {
            Button {
                Task { await downloader.baixar(.transcricao, sessionId: sessionId, transcriptId: transcriptId) }
            } label: {
                Label("Transcrição em PDF", systemImage: "text.alignleft")
            }
            Button {
                Task { await downloader.baixar(.resumo, sessionId: sessionId, transcriptId: transcriptId) }
            } label: {
                Label(resumoPronto ? "Resumo em PDF" : "Resumo em PDF (gere o resumo primeiro)", systemImage: "sparkles")
            }
            .disabled(!resumoPronto)
        } label: {
            Group {
                if downloader.baixando != nil {
                    ProgressView().controlSize(.small).tint(Theme.primary)
                } else {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                }
            }
            .frame(width: 44, height: 42)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.border, lineWidth: 1))
        }
        .disabled(downloader.baixando != nil)
        .accessibilityLabel("Baixar em PDF")
        .transcriptPDFPreview(downloader)
    }
}

// MARK: - Botão do resumo no cartão da lista

/// "Gerar resumo" / "Gerando resumo" / "Ver resumo" / "Tentar resumo de novo",
/// ao lado de "Ver transcrição" — como no CRM web. Mesmas regras do cartão do
/// resumo dentro da transcrição: nunca automático, um por transcrição.
struct TranscriptListSummaryButton: View {
    let sessionId: String
    let transcriptId: String
    let iaLigada: Bool
    /// Avisa o cartão quando o estado muda (o menu de PDF libera o resumo).
    let aoMudar: (TranscriptSummaryState) -> Void

    @State private var estado: TranscriptSummaryState
    @State private var gerando = false
    @State private var abrindo = false
    @State private var folha: TranscriptSummaryState? = nil
    @State private var erro: String? = nil

    init(
        sessionId: String,
        transcriptId: String,
        statusInicial: String?,
        iaLigada: Bool,
        aoMudar: @escaping (TranscriptSummaryState) -> Void
    ) {
        self.sessionId = sessionId
        self.transcriptId = transcriptId
        self.iaLigada = iaLigada
        self.aoMudar = aoMudar
        _estado = State(initialValue: TranscriptSummaryState(
            status: statusInicial ?? "NONE", conteudo: nil, geradoEm: nil, erro: nil
        ))
    }

    private var pronto: Bool { estado.status == "READY" }

    var body: some View {
        Group {
            if pronto {
                botao(titulo: "Ver resumo", icone: "sparkles", carregando: abrindo) {
                    Task { await abrir() }
                }
            } else if estado.isProcessing {
                botao(titulo: "Gerando resumo", icone: "sparkles", carregando: true) {}
                    .disabled(true)
            } else if iaLigada {
                botao(
                    titulo: estado.isFailed ? "Tentar resumo de novo" : "Gerar resumo",
                    icone: "sparkles",
                    carregando: gerando
                ) {
                    Task { await gerar() }
                }
            }
        }
        .task(id: estado.isProcessing) { await acompanhar() }
        .onChange(of: estado) { _, novo in aoMudar(novo) }
        .sheet(item: Binding(
            get: { folha.map(FolhaDoResumo.init) },
            set: { folha = $0?.estado }
        )) { item in
            TranscriptSummarySheet(sessionId: sessionId, transcriptId: transcriptId, estado: item.estado)
        }
        .alert("Resumo", isPresented: Binding(get: { erro != nil }, set: { if !$0 { erro = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(erro ?? "")
        }
    }

    private struct FolhaDoResumo: Identifiable {
        let estado: TranscriptSummaryState
        var id: String { estado.status + (estado.geradoEm?.description ?? "") }
    }

    private func botao(titulo: String, icone: String, carregando: Bool, acao: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            acao()
        } label: {
            HStack(spacing: 7) {
                if carregando {
                    ProgressView().controlSize(.small).tint(RecAi.accent)
                } else {
                    Image(systemName: icone).font(.system(size: 13, weight: .semibold))
                }
                Text(titulo)
                    .font(Theme.body(14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(RecAi.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(RecAi.soft.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.pressable)
        .disabled(carregando)
    }

    /// A lista só traz o status; o conteúdo vem ao abrir.
    @MainActor
    private func abrir() async {
        if estado.isReady { folha = estado; return }
        abrindo = true
        defer { abrindo = false }
        do {
            let atual = try await TranscriptsAPI.resumo(sessionId: sessionId, transcriptId: transcriptId)
            estado = atual
            if atual.isReady { folha = atual }
        } catch let error as APIError {
            erro = error.message
        } catch {
            erro = "Não foi possível abrir o resumo."
        }
    }

    @MainActor
    private func gerar() async {
        gerando = true
        defer { gerando = false }
        do {
            estado = try await TranscriptsAPI.gerarResumo(sessionId: sessionId, transcriptId: transcriptId)
        } catch let error as APIError where error.statusCode == 409 {
            // Já existe (gerado em outro aparelho): vira "Ver resumo".
            if let atual = try? await TranscriptsAPI.resumo(sessionId: sessionId, transcriptId: transcriptId) {
                estado = atual
            }
        } catch let error as APIError {
            erro = error.message
        } catch {
            erro = "Não foi possível pedir o resumo. Tente de novo."
        }
    }

    /// Enquanto gera, confere a cada 3 s; a task cai quando sai de PROCESSING.
    @MainActor
    private func acompanhar() async {
        guard estado.isProcessing else { return }
        while !Task.isCancelled && estado.isProcessing {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            if let atual = try? await TranscriptsAPI.resumo(sessionId: sessionId, transcriptId: transcriptId) {
                if atual.isReady { Haptics.success() }
                if atual.isFailed {
                    Haptics.warning()
                    erro = atual.erro ?? "Não foi possível gerar o resumo. Tente de novo."
                }
                estado = atual
            }
        }
    }
}

/// Folha "Resumo da chamada": o mesmo cartão do resumo da transcrição (com o botão de PDF).
struct TranscriptSummarySheet: View {
    let sessionId: String
    let transcriptId: String
    let estado: TranscriptSummaryState

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TranscriptSummaryCard(sessionId: sessionId, transcriptId: transcriptId, inicial: estado)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 16)
            }
            .background(Theme.background)
            .navigationTitle("Resumo da chamada")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fechar") { dismiss() }
                        .font(Theme.body(15))
                }
            }
        }
        .presentationDetents([.large])
    }
}
