import SwiftUI

// MARK: - Suporte — porta de entrada
//
// Uma tela só: atendimento aberto em destaque (ou "Como podemos ajudar?"
// quando não há nenhum) e os finalizados abaixo, como histórico. O título
// vem da casca (item do menu), por isso não há `setToolbarTitle` aqui.

struct SupportHomeView: View {
    @State private var store = SupportStore.shared
    @State private var deepLink = DeepLink.shared
    @State private var openChat: SupChatRoute?
    @State private var openingId: String?
    @State private var isRetrying = false

    @State private var categoria: SupCategory?
    @State private var texto = ""
    @State private var isCreating = false
    @State private var createError: String?
    @FocusState private var textoFocado: Bool

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    conteudo
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.loadTickets() }
        }
        .task {
            consumirDeepLink()
            await store.loadTickets()
        }
        .onChange(of: deepLink.supportTicketId) { _, _ in consumirDeepLink() }
        .onChange(of: openChat) { _, rota in
            if rota == nil { openingId = nil }
        }
        .navigationDestination(item: $openChat) { rota in
            SupportChatView(ticketId: rota.id)
        }
    }

    private func consumirDeepLink() {
        guard let id = deepLink.supportTicketId else { return }
        deepLink.supportTicketId = nil
        abrir(id)
    }

    private func abrir(_ id: String) {
        Haptics.tap()
        openingId = id
        openChat = SupChatRoute(id: id)
    }

    // MARK: Conteúdo

    @ViewBuilder
    private var conteudo: some View {
        if !store.hasLoadedTickets, store.isLoadingTickets || store.ticketsError == nil {
            SkeletonCard(linhas: 3)
            SkeletonCard(linhas: 2)
        } else if !store.hasLoadedTickets, let erro = store.ticketsError {
            falha(erro)
        } else {
            if let aberto = store.openTicket {
                cartaoAberto(aberto)
            } else {
                novoAtendimento
            }
            avisoPrivacidade
            if !store.resolvedTickets.isEmpty {
                historico
            }
        }
    }

    private func falha(_ erro: String) -> some View {
        VStack(spacing: 14) {
            Text(erro)
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            RetryButton(isLoading: isRetrying) {
                Task {
                    isRetrying = true
                    await store.loadTickets()
                    isRetrying = false
                }
            }
        }
        .padding(.top, 60)
    }

    private var avisoPrivacidade: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("Não envie dados de pacientes por aqui. O suporte não precisa deles para te ajudar.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: Atendimento aberto

    private func cartaoAberto(_ ticket: SupTicket) -> some View {
        Button {
            abrir(ticket.id)
        } label: {
            ThemeCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("ATENDIMENTO EM ANDAMENTO")
                            .font(Theme.body(10, weight: .semibold))
                            .tracking(1.1)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        seloStatus(ticket.status)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 44, height: 44)
                            .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("#\(ticket.number) · \(ticket.title)")
                                .font(Theme.serifTitle(18))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(linhaEspera(ticket))
                                .font(Theme.body(12, weight: .medium))
                                .foregroundStyle(ticket.waitingFor == .therapist ? Theme.primary : Theme.textSecondary)
                        }
                        Spacer(minLength: 6)
                        if ticket.unread > 0 {
                            contador(ticket.unread)
                        }
                    }
                    if let ultima = ticket.lastMessage {
                        Divider().overlay(Theme.border)
                        HStack(spacing: 8) {
                            Text(previa(ultima))
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Text(NotifRelativeTime.format(ultima.createdAt))
                                .font(Theme.body(11, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    HStack(spacing: 6) {
                        Text("Abrir conversa")
                            .font(Theme.body(14, weight: .semibold))
                        if openingId == ticket.id {
                            ProgressView().controlSize(.small).tint(Theme.primary)
                        } else {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .foregroundStyle(Theme.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.pressableSubtle)
        .accessibilityIdentifier("supportOpenTicket")
    }

    private func linhaEspera(_ ticket: SupTicket) -> String {
        switch ticket.waitingFor {
        case .therapist:
            if let nome = ticket.assignedAdmin?.name { return "\(nome) respondeu" }
            return "O suporte respondeu"
        case .admin:
            if let nome = ticket.assignedAdmin?.name { return "\(nome) está cuidando do seu atendimento" }
            return "Aguardando alguém do time responder"
        default:
            return "Aberto em \(SupFormat.dataCurta.string(from: ticket.createdAt))"
        }
    }

    private func previa(_ ultima: SupLastMessage) -> String {
        let texto = ultima.preview ?? "Mensagem"
        return ultima.senderRole == .therapist ? "Você: \(texto)" : texto
    }

    private func contador(_ valor: Int) -> some View {
        Text(valor > 99 ? "99+" : "\(valor)")
            .font(Theme.body(12, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .background(Theme.danger, in: Capsule())
            .accessibilityLabel("\(valor) mensagens não lidas")
    }

    private func seloStatus(_ status: SupTicketStatus) -> StatusBadge {
        switch status {
        case .open: StatusBadge(label: status.label, color: Theme.warning, background: Theme.warningSoft)
        case .inProgress: StatusBadge(label: status.label, color: Theme.primary, background: Theme.primarySoft)
        case .resolved: StatusBadge(label: status.label, color: Theme.success, background: Theme.successSoft)
        case .unknown: StatusBadge(label: status.label, color: Theme.textSecondary, background: Theme.border)
        }
    }

    // MARK: Novo atendimento

    private var novoAtendimento: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Como podemos ajudar?")
                        .font(Theme.serifTitle(22))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Conte o que aconteceu. O time da Terapia Acolher responde por aqui mesmo.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("ASSUNTO")
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.textSecondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(SupCategory.allCases) { item in
                        botaoCategoria(item)
                    }
                }

                Text("SUA MENSAGEM")
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.textSecondary)
                ZStack(alignment: .topLeading) {
                    if texto.isEmpty {
                        Text("Ex.: meu saque de ontem ainda não caiu na conta.")
                            .font(Theme.body(15))
                            .foregroundStyle(Theme.textSecondary.opacity(0.8))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $texto)
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .focused($textoFocado)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .frame(minHeight: 120)
                        .accessibilityLabel("Sua mensagem para o suporte")
                }
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(textoFocado ? Theme.primary : Theme.border, lineWidth: 1))

                if let createError {
                    Label(createError, systemImage: "exclamationmark.circle")
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(Theme.danger)
                }

                PrimaryButton(
                    title: "Enviar para o suporte",
                    icon: "paperplane",
                    isLoading: isCreating,
                    isEnabled: !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    Task { await criar() }
                }
                .accessibilityIdentifier("supportCreate")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func botaoCategoria(_ item: SupCategory) -> some View {
        let selecionada = categoria == item
        return Button {
            Haptics.tap()
            categoria = selecionada ? nil : item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                Text(item.label)
                    .font(Theme.body(13, weight: selecionada ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selecionada ? .white : Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selecionada ? Theme.ink : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: selecionada ? 0 : 1))
            .animation(.easeOut(duration: 0.15), value: selecionada)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selecionada ? .isSelected : [])
    }

    private func criar() async {
        let conteudo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !conteudo.isEmpty else { return }
        guard conteudo.count <= 4000 else {
            createError = "A mensagem pode ter no máximo 4.000 caracteres."
            return
        }
        isCreating = true
        createError = nil
        defer { isCreating = false }
        do {
            let criado = try await SupportAPI.createTicket(category: categoria, text: conteudo)
            store.didCreate(criado.ticket)
            texto = ""
            categoria = nil
            textoFocado = false
            Haptics.success()
            abrir(criado.ticket.id)
        } catch let error as APIError where error.statusCode == 409 {
            // Já havia um aberto (outro aparelho, por exemplo): leva até ele.
            await store.loadTickets()
            if let id = store.openTicketId {
                abrir(id)
            } else {
                createError = error.message
            }
        } catch is CancellationError {
            return
        } catch {
            createError = (error as? APIError)?.message
                ?? "Não foi possível enviar agora. Confira a conexão e tente de novo."
        }
    }

    // MARK: Histórico

    private var historico: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ATENDIMENTOS ANTERIORES")
                .font(Theme.body(10, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 4)
            ThemeCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(store.resolvedTickets.enumerated()), id: \.element.id) { indice, ticket in
                        if indice > 0 {
                            InsetDivider(leading: 14 + 38 + 12)
                        }
                        linhaHistorico(ticket)
                    }
                }
            }
        }
    }

    private func linhaHistorico(_ ticket: SupTicket) -> some View {
        Button {
            abrir(ticket.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.bubble")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.success)
                    .frame(width: 38, height: 38)
                    .background(Theme.successSoft, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("#\(ticket.number) · \(ticket.title)")
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(ticket.resolvedAt.map { "Finalizado em \(SupFormat.dataCurta.string(from: $0))" } ?? "Finalizado")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                if openingId == ticket.id {
                    ProgressView().controlSize(.small).tint(Theme.primary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.6))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
    }
}
