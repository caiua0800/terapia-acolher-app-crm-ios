import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Acolher Financeiro — o que o Asaas ainda pede (conta em análise)
//
// Com o Asaas real a identidade não passa pela nossa câmera: depois do envio,
// ele devolve grupos de documento. Grupo com `onboardingUrl` abre a página
// segura dele DENTRO do app (SFSafariViewController — câmera e prova de vida
// funcionam lá); grupo com `uploadInApp` sobe o arquivo pelo nosso backend.

struct GwProviderDocumentsCard: View {
    let account: GwAccount
    let providerName: String
    /// Recarrega a conta — ao fechar a página do Asaas, por exemplo.
    let onReload: () async -> Void

    @State private var store = FinGatewayStore.shared
    @State private var paginaAberta: DocWebLink?
    /// Uma flag por ação e por item (regra do projeto).
    @State private var renovandoLinkId: String?
    @State private var enviandoId: String?
    @State private var escolhendoOrigem: GwProviderDocument?
    /// Alvo do arquivo em escolha. Bool próprio para cada seletor: amarrar o
    /// `isPresented` ao alvo zerava o alvo antes de a seleção chegar.
    @State private var alvo: GwProviderDocument?
    @State private var mostrandoGaleria = false
    @State private var fotoSelecionada: PhotosPickerItem?
    @State private var importandoPDF = false
    @State private var capturando: GwProviderDocument?
    @State private var errorMessage: String?

    private static let limiteBytes = 10 * 1024 * 1024

    private var pendencias: [GwProviderDocument] { account.pendenciasDoProvedor }
    private var algumPeloLink: Bool { pendencias.contains { $0.enviaPeloLink } }
    private var ocupado: Bool { renovandoLinkId != nil || enviandoId != nil }

    var body: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("DOCUMENTOS PARA O \(providerName.uppercased())")
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.textSecondary)

                if pendencias.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 22)
                        Text("Seus documentos estão em análise pelo \(providerName). Você recebe um aviso quando a conta for aprovada.")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("gwProvedorSemPendencias")
                } else {
                    if algumPeloLink {
                        notaDaPaginaSegura
                    }
                    ForEach(Array(pendencias.enumerated()), id: \.element.id) { indice, documento in
                        if indice > 0 { Divider().overlay(Theme.border) }
                        linha(documento)
                    }
                }

                if let errorMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                        Text(errorMessage)
                            .font(Theme.body(13, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.danger)
                    .padding(12)
                    .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $paginaAberta, onDismiss: {
            Task { await onReload() }
        }) { link in
            DocSafariView(url: link.url)
                .ignoresSafeArea()
                // Arrastar para fechar no meio da prova de vida perde tudo; o
                // "OK" da própria página continua fechando.
                .interactiveDismissDisabled()
        }
        .confirmationDialog(
            "Enviar documento",
            isPresented: .init(
                get: { escolhendoOrigem != nil },
                set: { if !$0 { escolhendoOrigem = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let documento = escolhendoOrigem {
                if FinGatewayCameraView.isAvailable {
                    Button("Tirar foto agora") { capturando = documento }
                }
                Button("Escolher da galeria") {
                    alvo = documento
                    mostrandoGaleria = true
                }
                Button("Escolher um PDF") {
                    alvo = documento
                    importandoPDF = true
                }
                Button("Cancelar", role: .cancel) {}
            }
        } message: {
            Text(escolhendoOrigem?.description ?? "Foto (JPG ou PNG) ou PDF, até 10 MB.")
        }
        .fullScreenCover(item: $capturando) { documento in
            FinGatewayCameraView(
                modo: .documento,
                titulo: documento.titulo,
                onCapture: { imagens in
                    capturando = nil
                    guard let foto = imagens.last else { return }
                    Task { await enviarFoto(foto, para: documento) }
                },
                onCancel: { capturando = nil }
            )
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $mostrandoGaleria, selection: $fotoSelecionada, matching: .images)
        .onChange(of: fotoSelecionada) { _, item in
            guard let item, let documento = alvo else { return }
            alvo = nil
            fotoSelecionada = nil
            Task { await enviarDaGaleria(item, para: documento) }
        }
        .fileImporter(isPresented: $importandoPDF, allowedContentTypes: [.pdf]) { resultado in
            guard let documento = alvo else { return }
            alvo = nil
            importarPDF(resultado, para: documento)
        }
    }

    // MARK: Blocos

    private var notaDaPaginaSegura: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .frame(width: 22)
            Text("O envio é feito na página segura do \(providerName), nosso parceiro financeiro, com prova de vida. Ela abre aqui dentro do app.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.primarySoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }

    private func linha(_ documento: GwProviderDocument) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: documento.situacao == .recusado ? "exclamationmark.circle" : "doc.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(documento.situacao == .recusado ? Theme.danger : Theme.primary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(documento.titulo)
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let descricao = documento.description, !descricao.isEmpty {
                        Text(descricao)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    switch documento.situacao {
                    case .emAnalise:
                        Text("Em análise")
                            .font(Theme.body(12, weight: .medium))
                            .foregroundStyle(Theme.warning)
                    case .recusado:
                        Text("Recusado — envie de novo")
                            .font(Theme.body(12, weight: .medium))
                            .foregroundStyle(Theme.danger)
                    case .naoEnviado:
                        EmptyView()
                    }
                }
                Spacer(minLength: 8)
                badge(documento.situacao)
            }

            if documento.enviaPeloLink {
                SecondaryButton(
                    title: documento.situacao == .recusado ? "Enviar de novo" : "Enviar documentos",
                    icon: "arrow.up.forward.app",
                    isLoading: renovandoLinkId == documento.id,
                    isEnabled: !ocupado,
                    tint: Theme.primary
                ) {
                    Task { await abrirPagina(documento) }
                }
                .accessibilityIdentifier("gwProvedorLink-\(documento.id)")
            } else if documento.enviaPeloApp {
                SecondaryButton(
                    title: documento.situacao == .recusado ? "Enviar de novo" : "Enviar arquivo",
                    icon: "paperclip",
                    isLoading: enviandoId == documento.id,
                    isEnabled: !ocupado,
                    tint: Theme.primary
                ) {
                    errorMessage = nil
                    escolhendoOrigem = documento
                }
                .accessibilityIdentifier("gwProvedorArquivo-\(documento.id)")
            }
        }
    }

    private func badge(_ situacao: GwProviderDocument.Situacao) -> StatusBadge {
        switch situacao {
        case .naoEnviado:
            .init(label: situacao.rotulo, color: Theme.textSecondary, background: Theme.border.opacity(0.5))
        case .emAnalise:
            .init(label: situacao.rotulo, color: Theme.warning, background: Theme.warningSoft)
        case .recusado:
            .init(label: situacao.rotulo, color: Theme.danger, background: Theme.dangerSoft)
        }
    }

    // MARK: Ações

    /// Link vigente abre na hora; vencido, busca a conta de novo (o backend
    /// devolve um link novo) e abre o do mesmo grupo.
    private func abrirPagina(_ documento: GwProviderDocument) async {
        errorMessage = nil
        guard documento.linkExpirado else {
            if let url = documento.linkDeEnvio { paginaAberta = DocWebLink(url: url) }
            return
        }
        renovandoLinkId = documento.id
        defer { renovandoLinkId = nil }
        await onReload()
        let atual = store.account?.pendenciasDoProvedor.first { $0.id == documento.id }
        if let url = atual?.linkDeEnvio {
            paginaAberta = DocWebLink(url: url)
        } else if atual == nil {
            // Sumiu da lista: o Asaas já recebeu esse grupo.
            Haptics.success()
        } else {
            errorMessage = "Não foi possível abrir a página do \(providerName). Puxe a tela para atualizar e tente de novo."
            Haptics.warning()
        }
    }

    private func enviarDaGaleria(_ item: PhotosPickerItem, para documento: GwProviderDocument) async {
        enviandoId = documento.id
        guard let data = try? await item.loadTransferable(type: Data.self),
              let imagem = UIImage(data: data)
        else {
            enviandoId = nil
            errorMessage = "Não foi possível ler a imagem escolhida. Tente outra."
            return
        }
        await enviarFoto(imagem, para: documento)
    }

    private func enviarFoto(_ imagem: UIImage, para documento: GwProviderDocument) async {
        guard let data = GwImage.downscaledJPEG(imagem, ladoMaximo: GwImage.ladoMaximoProvedor) else {
            enviandoId = nil
            errorMessage = "Não foi possível ler a foto. Tente de novo."
            return
        }
        await enviar(documento, data: data, fileName: "documento.jpg", mimeType: "image/jpeg")
    }

    private func importarPDF(_ resultado: Result<URL, Error>, para documento: GwProviderDocument) {
        switch resultado {
        case let .success(url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                errorMessage = "Não foi possível ler o arquivo escolhido."
                return
            }
            Task { await enviar(documento, data: data, fileName: "documento.pdf", mimeType: "application/pdf") }
        case .failure:
            errorMessage = "Não foi possível importar o arquivo."
        }
    }

    private func enviar(_ documento: GwProviderDocument, data: Data, fileName: String, mimeType: String) async {
        guard data.count <= Self.limiteBytes else {
            enviandoId = nil
            errorMessage = "O arquivo passa de 10 MB. Escolha um menor."
            Haptics.warning()
            return
        }
        errorMessage = nil
        enviandoId = documento.id
        defer { enviandoId = nil }
        do {
            let conta = try await FinGatewayAPI.uploadProviderDocument(
                groupId: documento.id,
                data: data,
                fileName: fileName,
                mimeType: mimeType
            )
            store.apply(conta)
            Haptics.success()
        } catch is CancellationError {
        } catch {
            errorMessage = (error as? APIError)?.message
                ?? "Não foi possível enviar o documento."
            Haptics.warning()
        }
    }
}
