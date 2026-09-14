import PhotosUI
import SwiftUI
import UIKit

// MARK: - Conversa com o suporte

struct SupportChatView: View {
    @State private var model: SupportChatModel
    @State private var store = SupportStore.shared
    @State private var recorder = SupAudioRecorder()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var isPreparingMedia = false
    @State private var showMicDenied = false
    @State private var isStartingRecording = false
    @State private var nearBottom = true
    @FocusState private var composerFocused: Bool

    init(ticketId: String) {
        _model = State(initialValue: SupportChatModel(
            ticketId: ticketId,
            ticket: SupportStore.shared.tickets.first { $0.id == ticketId }
        ))
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                faixaStatus
                if model.messages.isEmpty, model.outgoing.isEmpty, model.isLoading || model.loadError == nil {
                    carregando
                } else if model.messages.isEmpty, let erro = model.loadError {
                    falha(erro)
                } else {
                    lista
                }
                rodape
            }
        }
        .setToolbarTitle(model.ticket.map { "Atendimento #\($0.number)" } ?? "Atendimento")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.appear() }
        .onDisappear {
            model.disappear()
            SupAudioPlayback.shared.stop()
            if recorder.phase == .recording { recorder.cancel() }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .any(of: [.images, .videos]))
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await prepararDaGaleria(item) }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: SupMediaPrep.documentTypes) { resultado in
            importar(resultado)
        }
        .alert("Ops", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("Microfone desativado", isPresented: $showMicDenied) {
            Button("Abrir Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Agora não", role: .cancel) {}
        } message: {
            Text("Para gravar áudio, permita o acesso ao microfone em Ajustes > Terapia Acolher.")
        }
    }

    // MARK: Estados

    private var carregando: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().tint(Theme.primary)
            Text("Abrindo a conversa…")
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func falha(_ erro: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Text(erro)
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            RetryButton(isLoading: model.isLoading) {
                Task { await model.load() }
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }

    /// Quem está cuidando, ou que a conexão está voltando.
    @ViewBuilder
    private var faixaStatus: some View {
        let reconectando = store.connection == .waiting
        if reconectando || model.ticket != nil {
            HStack(spacing: 8) {
                if reconectando {
                    ProgressView().controlSize(.mini).tint(Theme.warning)
                    Text("Reconectando… as mensagens chegam assim que voltar.")
                } else if let ticket = model.ticket {
                    Circle()
                        .fill(ticket.status.isResolved ? Theme.success : (ticket.assignedAdmin == nil ? Theme.warning : Theme.primary))
                        .frame(width: 7, height: 7)
                    Text(textoStatus(ticket))
                }
                Spacer(minLength: 0)
            }
            .font(Theme.body(12, weight: .medium))
            .foregroundStyle(reconectando ? Theme.warning : Theme.textSecondary)
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 8)
            .background(reconectando ? Theme.warningSoft : Theme.surface)
            .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
            .animation(.easeInOut(duration: 0.2), value: reconectando)
        }
    }

    private func textoStatus(_ ticket: SupTicket) -> String {
        if ticket.status.isResolved { return "Atendimento finalizado" }
        let assunto = SupCategory.label(for: ticket.category).map { " · \($0)" } ?? ""
        if let nome = ticket.assignedAdmin?.name { return "\(nome) está cuidando do seu atendimento\(assunto)" }
        return "Aguardando alguém do time\(assunto)"
    }

    // MARK: Lista

    private enum Linha: Identifiable {
        case dia(Date)
        case mensagem(SupMessage, mostrarNome: Bool)
        case envio(SupOutgoing)

        var id: String {
            switch self {
            case let .dia(data): "dia-\(Int(data.timeIntervalSince1970))"
            case let .mensagem(mensagem, _): mensagem.id
            case let .envio(item): item.clientId
            }
        }
    }

    private var linhas: [Linha] {
        var resultado: [Linha] = []
        let calendario = Calendar.current
        var diaAtual: Date?
        var ultimoRemetente: String?
        for mensagem in model.messages {
            let dia = calendario.startOfDay(for: mensagem.createdAt)
            if diaAtual != dia {
                resultado.append(.dia(dia))
                diaAtual = dia
                ultimoRemetente = nil
            }
            let chave: String = mensagem.isSystem
                ? "sistema"
                : (mensagem.isMine ? "eu" : (mensagem.sender?.id ?? mensagem.sender?.name ?? "suporte"))
            resultado.append(.mensagem(
                mensagem,
                mostrarNome: !mensagem.isMine && !mensagem.isSystem && chave != ultimoRemetente
            ))
            ultimoRemetente = chave
        }
        if !model.outgoing.isEmpty {
            let hoje = calendario.startOfDay(for: Date())
            if diaAtual != hoje { resultado.append(.dia(hoje)) }
            resultado += model.outgoing.map { Linha.envio($0) }
        }
        return resultado
    }

    private var lista: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if model.hasMoreOlder {
                        ProgressView()
                            .tint(Theme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .onAppear { carregarAntigas(proxy) }
                    } else {
                        inicioConversa
                    }
                    ForEach(linhas) { linha in
                        linhaView(linha).id(linha.id)
                    }
                    if let nome = model.typingName {
                        SupTypingBubble(name: nome)
                            .id("digitando")
                            .transition(.opacity)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("fim")
                        .onAppear { nearBottom = true }
                        .onDisappear { nearBottom = false }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .animation(.easeOut(duration: 0.18), value: model.typingName)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.last?.id) { _, _ in
                if nearBottom || model.messages.last?.isMine == true {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("fim", anchor: .bottom) }
                }
            }
            .onChange(of: model.outgoing.count) { antes, depois in
                guard depois > antes else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("fim", anchor: .bottom) }
            }
            .onChange(of: model.typingName) { _, nome in
                guard nome != nil, nearBottom else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("fim", anchor: .bottom) }
            }
            .onChange(of: composerFocused) { _, focado in
                guard focado else { return }
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("fim", anchor: .bottom) }
                }
            }
        }
    }

    private var inicioConversa: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12, weight: .semibold))
            Text("Não envie dados de pacientes por aqui. Esta conversa fica guardada no seu histórico de atendimentos.")
                .font(Theme.body(11.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func carregarAntigas(_ proxy: ScrollViewProxy) {
        guard !model.isLoadingOlder, let ancora = model.messages.first?.id else { return }
        Task {
            await model.loadOlder()
            proxy.scrollTo(ancora, anchor: .top)
        }
    }

    @ViewBuilder
    private func linhaView(_ linha: Linha) -> some View {
        switch linha {
        case let .dia(data):
            SupDaySeparator(date: data)
        case let .mensagem(mensagem, mostrarNome):
            if mensagem.isSystem {
                SupSystemNote(message: mensagem)
            } else {
                SupMessageBubble(
                    message: mensagem,
                    showName: mostrarNome,
                    seen: mensagem.id == model.lastSeenMineId,
                    renew: { id in await model.renewAttachment(messageId: id) }
                )
            }
        case let .envio(item):
            SupOutgoingBubble(
                item: item,
                onRetry: { model.retry(item.clientId) },
                onDiscard: { model.discard(item.clientId) }
            )
        }
    }

    // MARK: Rodapé

    @ViewBuilder
    private var rodape: some View {
        if model.isResolved {
            finalizado
        } else if recorder.phase == .recording {
            gravando
        } else {
            compositor
        }
    }

    private var finalizado: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.success)
                Text(textoFinalizado)
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            SecondaryButton(
                title: outroAberto ? "Ver atendimento em andamento" : "Abrir novo atendimento",
                icon: outroAberto ? "arrow.right" : "plus.bubble",
                tint: Theme.primary
            ) {
                dismiss()
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Theme.surface)
        .overlay(alignment: .top) { Divider().overlay(Theme.border) }
    }

    private var outroAberto: Bool {
        guard let aberto = store.openTicketId else { return false }
        return aberto != model.ticketId
    }

    private var textoFinalizado: String {
        guard let data = model.ticket?.resolvedAt else { return "Atendimento finalizado." }
        return "Atendimento finalizado em \(SupFormat.dataHora.string(from: data))."
    }

    private var textoVazio: Bool {
        model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var compositor: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Button {
                    showPhotos = true
                } label: {
                    Label("Foto ou vídeo", systemImage: "photo.on.rectangle")
                }
                Button {
                    showFiles = true
                } label: {
                    Label("Arquivo (PDF, planilha, documento)", systemImage: "doc")
                }
            } label: {
                ZStack {
                    if isPreparingMedia {
                        ProgressView().controlSize(.small).tint(Theme.primary)
                    } else {
                        Image(systemName: "paperclip")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
            }
            .disabled(isPreparingMedia)
            .accessibilityLabel(isPreparingMedia ? "Preparando anexo" : "Anexar foto, vídeo ou arquivo")

            TextField("Escreva sua mensagem", text: $model.draft, axis: .vertical)
                .font(Theme.body(15))
                .lineLimit(1 ... 5)
                .focused($composerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(composerFocused ? Theme.primary.opacity(0.6) : Theme.border, lineWidth: 1))
                .onChange(of: model.draft) { _, _ in model.draftChanged() }
                .accessibilityIdentifier("supportComposer")

            if textoVazio {
                Button {
                    Task { await comecarGravacao() }
                } label: {
                    ZStack {
                        if isStartingRecording {
                            ProgressView().controlSize(.small).tint(Theme.primary)
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.primary)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .background(Theme.primarySoft, in: Circle())
                }
                .buttonStyle(.pressable)
                .disabled(isStartingRecording)
                .accessibilityLabel("Gravar áudio")
            } else {
                Button {
                    model.sendDraft()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.primary, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Enviar mensagem")
                .accessibilityIdentifier("supportSend")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface)
        .overlay(alignment: .top) { Divider().overlay(Theme.border) }
    }

    private var gravando: some View {
        HStack(spacing: 12) {
            Button {
                recorder.cancel()
                Haptics.warning()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.danger)
                    .frame(width: 40, height: 40)
                    .background(Theme.dangerSoft, in: Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Cancelar gravação")

            HStack(spacing: 8) {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(Theme.danger)
                    .symbolEffect(.pulse)
                Text(SupFormat.duracao(recorder.elapsed))
                    .font(Theme.money(16))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                Text("de 5:00")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Gravando, \(SupFormat.duracao(recorder.elapsed)) de 5 minutos")

            Spacer(minLength: 0)

            Button {
                enviarGravacao()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.primary, in: Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Parar e enviar áudio")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface)
        .overlay(alignment: .top) { Divider().overlay(Theme.border) }
    }

    // MARK: Ações

    private func comecarGravacao() async {
        isStartingRecording = true
        defer { isStartingRecording = false }
        guard await recorder.requestPermission() else {
            showMicDenied = true
            return
        }
        SupAudioPlayback.shared.stop()
        composerFocused = false
        let recorder = recorder
        let model = model
        recorder.onLimitReached = {
            if let arquivo = recorder.finish() { model.send(file: arquivo) }
        }
        do {
            try recorder.start()
            Haptics.tap()
        } catch {
            model.errorMessage = (error as? SupPrepError)?.message ?? "Não foi possível gravar agora."
        }
    }

    private func enviarGravacao() {
        guard let arquivo = recorder.finish() else {
            model.errorMessage = "O áudio ficou curto demais. Segure a gravação por pelo menos 1 segundo."
            return
        }
        Haptics.tap()
        model.send(file: arquivo)
    }

    private func prepararDaGaleria(_ item: PhotosPickerItem) async {
        isPreparingMedia = true
        defer {
            isPreparingMedia = false
            photoItem = nil
        }
        do {
            let arquivo = try await SupMediaPrep.fromPhotosItem(item)
            model.send(file: arquivo)
        } catch is CancellationError {
            return
        } catch {
            model.errorMessage = (error as? SupPrepError)?.message ?? "Não foi possível preparar esse arquivo."
        }
    }

    private func importar(_ resultado: Result<URL, Error>) {
        switch resultado {
        case let .success(url):
            do {
                model.send(file: try SupMediaPrep.fromImportedFile(url))
            } catch {
                model.errorMessage = (error as? SupPrepError)?.message ?? "Não foi possível abrir o arquivo."
            }
        case .failure:
            model.errorMessage = "Não foi possível abrir o arquivo."
        }
    }
}

// MARK: - Peças da conversa

private struct SupDaySeparator: View {
    let date: Date

    var body: some View {
        Text(SupFormat.dia(date))
            .font(Theme.body(11, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.border.opacity(0.55), in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SupSystemNote: View {
    let message: SupMessage

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .semibold))
            Text(message.text ?? "")
                .font(Theme.body(12, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct SupTypingBubble: View {
    let name: String

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                Text("\(name) está digitando…")
                    .font(Theme.body(12, weight: .medium))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
            Spacer(minLength: 48)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct SupMessageBubble: View {
    let message: SupMessage
    let showName: Bool
    let seen: Bool
    let renew: SupRenew

    private var midiaGrande: Bool { message.type == .image || message.type == .video }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.isMine { Spacer(minLength: 52) }
            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 3) {
                if showName {
                    Text("\(message.sender?.name ?? "Suporte") · Terapia Acolher")
                        .font(Theme.body(11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 4)
                        .padding(.top, 6)
                }
                balao
                HStack(spacing: 4) {
                    Text(SupFormat.hora.string(from: message.createdAt))
                    if message.isMine, seen {
                        Text("· Visto")
                    }
                }
                .font(Theme.body(10.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 4)
            }
            if !message.isMine { Spacer(minLength: 52) }
        }
        .accessibilityElement(children: .contain)
    }

    private var balao: some View {
        let texto = message.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return VStack(alignment: .leading, spacing: 6) {
            if let anexo = message.attachment {
                conteudoAnexo(anexo)
            }
            if !texto.isEmpty {
                Text(texto)
                    .font(Theme.body(15))
                    .foregroundStyle(message.isMine ? .white : Theme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, midiaGrande ? 8 : 0)
                    .padding(.bottom, midiaGrande ? 4 : 0)
                    .accessibilityLabel(message.isMine ? "Você: \(texto)" : "\(message.sender?.name ?? "Suporte"): \(texto)")
            }
        }
        .padding(midiaGrande ? 4 : 0)
        .padding(.horizontal, midiaGrande ? 0 : 12)
        .padding(.vertical, midiaGrande ? 0 : 9)
        .background(
            message.isMine ? Theme.primary : Theme.surface,
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(message.isMine ? Color.clear : Theme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func conteudoAnexo(_ anexo: SupAttachment) -> some View {
        switch message.type {
        case .image:
            SupRemoteImage(messageId: message.id, attachment: anexo, renew: renew)
        case .video:
            SupVideoAttachment(messageId: message.id, attachment: anexo, renew: renew)
        case .audio:
            SupAudioAttachment(messageId: message.id, attachment: anexo, renew: renew, isMine: message.isMine)
        default:
            if anexo.contentType.hasPrefix("image/") {
                SupRemoteImage(messageId: message.id, attachment: anexo, renew: renew)
            } else if anexo.contentType.hasPrefix("audio/") {
                SupAudioAttachment(messageId: message.id, attachment: anexo, renew: renew, isMine: message.isMine)
            } else if anexo.contentType.hasPrefix("video/") {
                SupVideoAttachment(messageId: message.id, attachment: anexo, renew: renew)
            } else {
                SupFileAttachment(messageId: message.id, attachment: anexo, renew: renew, isMine: message.isMine)
            }
        }
    }
}

private struct SupOutgoingBubble: View {
    let item: SupOutgoing
    let onRetry: () -> Void
    let onDiscard: () -> Void

    private var falhou: String? {
        if case let .failed(motivo) = item.state { return motivo }
        return nil
    }

    private var progresso: Double? {
        if case let .sending(valor) = item.state { return valor }
        return nil
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 52)
            VStack(alignment: .trailing, spacing: 4) {
                balao
                rodape
            }
        }
    }

    private var balao: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let arquivo = item.file {
                previaLocal(arquivo)
            }
            if let texto = item.text, !texto.isEmpty {
                Text(texto)
                    .font(Theme.body(15))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, item.file?.preview != nil ? 4 : 12)
        .padding(.vertical, item.file?.preview != nil ? 4 : 9)
        .background(
            falhou == nil ? Theme.primary.opacity(0.78) : Theme.danger.opacity(0.85),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func previaLocal(_ arquivo: SupLocalFile) -> some View {
        if let imagem = arquivo.preview {
            ZStack {
                Image(uiImage: imagem)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 228, height: 160)
                    .clipped()
                if arquivo.kind == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.35), in: Circle())
                }
                if let progresso, falhou == nil {
                    Color.black.opacity(0.25)
                    SupProgressRing(value: progresso)
                }
            }
            .frame(width: 228, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(arquivo.kind == .video ? "Vídeo sendo enviado" : "Foto sendo enviada")
        } else {
            HStack(spacing: 10) {
                Image(systemName: arquivo.kind == .audio ? "waveform" : "doc")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(arquivo.kind == .audio ? "Áudio" : arquivo.fileName)
                        .font(Theme.body(14, weight: .semibold))
                        .lineLimit(1)
                    Text(detalhe(arquivo))
                        .font(Theme.body(11))
                        .opacity(0.85)
                }
                if let progresso, falhou == nil {
                    SupProgressRing(value: progresso, size: 22)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: 228, alignment: .leading)
        }
    }

    private func detalhe(_ arquivo: SupLocalFile) -> String {
        [SupFormat.duracao(ms: arquivo.durationMs), SupFormat.tamanho(arquivo.sizeBytes)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    @ViewBuilder
    private var rodape: some View {
        if let falhou {
            VStack(alignment: .trailing, spacing: 6) {
                Label(falhou, systemImage: "exclamationmark.circle.fill")
                    .font(Theme.body(11, weight: .medium))
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.trailing)
                HStack(spacing: 14) {
                    Button("Descartar", role: .destructive, action: onDiscard)
                        .font(Theme.body(12, weight: .semibold))
                    Button {
                        Haptics.tap()
                        onRetry()
                    } label: {
                        Label("Tentar de novo", systemImage: "arrow.clockwise")
                            .font(Theme.body(12, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 4)
        } else {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .semibold))
                if let progresso, item.file != nil, item.uploadId == nil {
                    Text("Enviando \(Int(progresso * 100))%")
                } else {
                    Text("Enviando…")
                }
            }
            .font(Theme.body(10.5, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 4)
            .accessibilityLabel("Enviando")
        }
    }
}

private struct SupProgressRing: View {
    let value: Double
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.35), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.04, min(value, 1)))
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.15), value: value)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Enviando \(Int(value * 100)) por cento")
    }
}
