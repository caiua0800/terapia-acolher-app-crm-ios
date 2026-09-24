import SwiftUI

// MARK: - Transcrições de todos os pacientes (menu)
//
// GET transcricoes — cabeçalho de cada transcrição com o paciente. Ler,
// gerar/ver o resumo e baixar em PDF reaproveitam o que a tela do paciente já
// usa (AgendaTranscriptSheet, TranscriptListSummaryButton, TranscriptPDFMenu).

struct GeneralTranscriptItem: Decodable, Identifiable, Hashable {
    let id: String
    let sessionId: String
    let paciente: GeneralPatientRef
    let sessaoIniciaEm: Date
    let sessaoTerminaEm: Date
    let iniciadaEm: Date?
    let terminadaEm: Date?
    let participantes: Int
    let trechos: Int
    let criadaEm: Date
    let resumoStatus: String?

    /// Duração real da chamada, quando o Google informou o fim.
    var duracao: String? {
        guard let fim = terminadaEm else { return nil }
        let minutos = Int(fim.timeIntervalSince(iniciadaEm ?? sessaoIniciaEm) / 60)
        guard minutos > 0 else { return nil }
        return minutos < 60 ? "\(minutos) min" : "\(minutos / 60)h\(String(format: "%02d", minutos % 60))"
    }
}

@Observable
final class GeneralTranscriptsViewModel {
    let filtros = GeneralListFilters()
    var itens: [GeneralTranscriptItem] = []
    var total = 0
    var pagina = 1
    var isLoading = true
    var carregandoMais = false
    var errorMessage: String? = nil
    var iaLigada = false

    /// Transcrição aberta na folha de leitura.
    var transcricao: AgendaTranscriptResponse? = nil
    var carregandoTranscricao = false
    var erroTranscricao: String? = nil
    var mostrarTranscricao = false
    var abrindoSessionId: String? = nil

    private var buscaTask: Task<Void, Never>?

    var temMais: Bool { itens.count < total }

    @MainActor
    func recarregar(mostrarEsqueleto: Bool = false) async {
        if mostrarEsqueleto || itens.isEmpty { isLoading = true }
        errorMessage = nil
        do {
            async let status = try? RecordsAPI.aiStatus()
            let pagina: GeneralPage<GeneralTranscriptItem> = try await APIClient.shared.get(
                "transcricoes", query: filtros.query(pagina: 1)
            )
            itens = pagina.itens
            total = pagina.total
            self.pagina = 1
            iaLigada = (await status)?.summaryEnabled ?? false
        } catch is CancellationError {
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar as transcrições."
        }
        isLoading = false
    }

    @MainActor
    func carregarMais() async {
        guard temMais, !carregandoMais else { return }
        carregandoMais = true
        do {
            let proxima: GeneralPage<GeneralTranscriptItem> = try await APIClient.shared.get(
                "transcricoes", query: filtros.query(pagina: pagina + 1)
            )
            itens += proxima.itens
            total = proxima.total
            pagina += 1
        } catch {
            // Falha no "carregar mais" não apaga o que já está na tela.
        }
        carregandoMais = false
    }

    @MainActor
    func buscaMudou() {
        buscaTask?.cancel()
        buscaTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.recarregar()
        }
    }

    @MainActor
    func abrir(_ sessionId: String) async {
        abrindoSessionId = sessionId
        carregandoTranscricao = true
        erroTranscricao = nil
        transcricao = nil
        mostrarTranscricao = true
        do {
            transcricao = try await TranscriptsAPI.daSessao(sessionId)
        } catch let error as APIError {
            erroTranscricao = error.message
        } catch {
            erroTranscricao = "Não foi possível abrir a transcrição."
        }
        carregandoTranscricao = false
        abrindoSessionId = nil
    }
}

struct GeneralTranscriptsView: View {
    @State private var model = GeneralTranscriptsViewModel()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    GeneralFilterBar(filtros: model.filtros, placeholder: "Buscar pelo nome do paciente")
                    Text(model.total == 1 ? "1 TRANSCRIÇÃO" : "\(model.total) TRANSCRIÇÕES")
                        .font(Theme.body(11, weight: .semibold))
                        .kerning(1.2)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 4)
                        .opacity(model.isLoading ? 0 : 1)
                    conteudo
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .refreshable { await model.recarregar() }
        }
        .task { if model.itens.isEmpty { await model.recarregar() } }
        .onChange(of: model.filtros.busca) { model.buscaMudou() }
        .onChange(of: model.filtros.periodo) { Task { await model.recarregar() } }
        .onChange(of: model.filtros.maisRecentes) { Task { await model.recarregar() } }
        .onChange(of: model.filtros.de) { Task { await model.recarregar() } }
        .onChange(of: model.filtros.ate) { Task { await model.recarregar() } }
        .onChange(of: model.filtros.usarDe) { Task { await model.recarregar() } }
        .onChange(of: model.filtros.usarAte) { Task { await model.recarregar() } }
        .sheet(isPresented: .init(
            get: { model.mostrarTranscricao },
            set: { model.mostrarTranscricao = $0 }
        )) {
            AgendaTranscriptSheet(
                response: model.transcricao,
                isLoading: model.carregandoTranscricao,
                errorMessage: model.erroTranscricao
            )
        }
    }

    @ViewBuilder
    private var conteudo: some View {
        if model.isLoading && model.itens.isEmpty {
            SkeletonList(linhas: 5, avatarSize: 42)
        } else if let erro = model.errorMessage, model.itens.isEmpty {
            ErrorRetryView(message: erro) { Task { await model.recarregar(mostrarEsqueleto: true) } }
                .padding(.top, 30)
        } else if model.itens.isEmpty {
            EmptyStateView(
                icon: "text.bubble",
                title: model.filtros.temFiltro ? "Nada com esses filtros" : "Nenhuma transcrição ainda",
                message: model.filtros.temFiltro
                    ? "Tente outro nome ou outro período."
                    : "As transcrições aparecem aqui alguns minutos depois de cada videochamada pelo link da Terapia Acolher."
            )
            .padding(.top, 30)
        } else {
            ForEach(model.itens) { item in
                GeneralTranscriptCard(
                    item: item,
                    abrindo: model.abrindoSessionId == item.sessionId,
                    iaLigada: model.iaLigada
                ) {
                    Task { await model.abrir(item.sessionId) }
                }
                .onAppear {
                    if item.id == model.itens.last?.id { Task { await model.carregarMais() } }
                }
            }
            if model.carregandoMais {
                ProgressView().tint(Theme.primary).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
        }
    }
}

private struct GeneralTranscriptCard: View {
    let item: GeneralTranscriptItem
    let abrindo: Bool
    let iaLigada: Bool
    let aoAbrir: () -> Void

    /// Estado do resumo vivo neste cartão (muda quando gera sem recarregar a lista).
    @State private var resumoStatus: String? = nil

    var body: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    InitialAvatar(name: item.paciente.name, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.paciente.name)
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text("Sessão de \(TranscriptsFormat.diaLongo(item.sessaoIniciaEm)) às \(TranscriptsFormat.hora(item.sessaoIniciaEm))")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                        Text(detalhes)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Button {
                        Haptics.tap()
                        aoAbrir()
                    } label: {
                        HStack(spacing: 8) {
                            if abrindo {
                                ProgressView().controlSize(.small).tint(Theme.primary)
                            } else {
                                Image(systemName: "text.alignleft").font(.system(size: 13, weight: .semibold))
                            }
                            Text("Ver transcrição").font(Theme.body(14, weight: .semibold))
                        }
                        .foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.primarySoft)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.pressable)
                    .disabled(abrindo)

                    TranscriptPDFMenu(
                        sessionId: item.sessionId,
                        transcriptId: item.id,
                        resumoPronto: (resumoStatus ?? item.resumoStatus) == "READY"
                    )
                }

                TranscriptListSummaryButton(
                    sessionId: item.sessionId,
                    transcriptId: item.id,
                    statusInicial: item.resumoStatus,
                    iaLigada: iaLigada
                ) { novo in
                    resumoStatus = novo.status
                }
            }
        }
    }

    private var detalhes: String {
        var partes: [String] = []
        if let d = item.duracao { partes.append(d) }
        partes.append(item.trechos == 1 ? "1 fala" : "\(item.trechos) falas")
        partes.append(item.participantes == 1 ? "1 participante" : "\(item.participantes) participantes")
        return partes.joined(separator: " · ")
    }
}
