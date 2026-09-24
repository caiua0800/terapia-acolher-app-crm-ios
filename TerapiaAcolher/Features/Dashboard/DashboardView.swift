import SwiftUI
import Observation

// MARK: - ViewModel

@Observable
final class DashboardViewModel {
    /// Instância única: o estado sobrevive à navegação.
    ///
    /// Antes cada tela criava o seu view model como `@State` local, então ele
    /// MORRIA ao sair — voltar para cá dois segundos depois dava spinner e
    /// requisição de novo. Era o que mais fazia o app parecer lento, mesmo com
    /// a API respondendo rápido. Agora a tela volta com o conteúdo já pintado e
    /// só atualiza por baixo.
    /// `var`: o logout troca por uma instância nova (ver SessionScope).
    static var shared = DashboardViewModel()

    var payload: DashPayload?
    var isLoading = false
    var errorMessage: String?
    /// Nova tentativa a partir do estado de erro — alimenta o spinner do
    /// próprio botão "Tentar de novo" (o spinner central já saiu de cena).
    var isRetrying = false

    @MainActor
    func load() async {
        if payload == nil { isLoading = true }
        if errorMessage != nil { isRetrying = true }
        errorMessage = nil
        defer { isLoading = false; isRetrying = false }
        do {
            payload = try await APIClient.shared.get("dashboard")
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar o painel. Verifique sua internet."
        }
    }
}

// MARK: - Tela Início

struct DashboardView: View {
    @State private var model = DashboardViewModel.shared
    @State private var profileStatus = ProfileStatusStore.shared
    @State private var deepLink = DeepLink.shared
    @State private var mostrandoPendencias = false
    @State private var vitrine = VitrineViewModel.shared
    @State private var leads = LeadsStore.shared

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if let payload = model.payload {
                content(payload)
            } else if model.isLoading {
                ProgressView()
                    .tint(Theme.primary)
            } else if let error = model.errorMessage {
                VStack(spacing: 14) {
                    EmptyStateView(
                        icon: "wifi.exclamationmark",
                        title: "Ops, não carregou",
                        message: error
                    )
                    RetryButton(isLoading: model.isRetrying) {
                        Task { await model.load() }
                    }
                }
            }
        }
        .onAppear {
            Task { await model.load() }
            Task { await avaliarPerfil() }
            // Só custa uma requisição e some sozinho se não estiver conectado.
            Task { await vitrine.load() }
            Task { await leads.load() }
        }
        .sheet(isPresented: $mostrandoPendencias) {
            ProfilePendingSheet(
                status: profileStatus.status,
                onIrParaPerfil: {
                    mostrandoPendencias = false
                    // O menu troca de seção e Configurações empurra o perfil.
                    deepLink.pendingSection = "configuracoes"
                    deepLink.abrirPerfil = true
                },
                onDepois: {
                    profileStatus.dispensadoNestaSessao = true
                    mostrandoPendencias = false
                }
            )
            .presentationDetents([.medium])
        }
    }

    /// Mostra o aviso de perfil incompleto no máximo uma vez por sessão.
    ///
    /// O Início é o único lugar onde ele cabe: é a primeira tela e a única que
    /// o terapeuta abre sem estar no meio de uma tarefa. Repetir a cada volta
    /// para cá transformaria o aviso em obstáculo.
    @MainActor
    private func avaliarPerfil() async {
        guard !profileStatus.dispensadoNestaSessao else { return }
        if profileStatus.status == nil { await profileStatus.refresh() }
        guard let status = profileStatus.status, status.temPendencia else { return }
        guard !mostrandoPendencias else { return }
        // Cinto e suspensório: se o convite de push ganhou a corrida, este
        // aviso espera a próxima abertura em vez de brigar pela janela.
        guard !PushOptIn.shared.mostrando else { return }
        profileStatus.dispensadoNestaSessao = true
        mostrandoPendencias = true
    }

    private func content(_ payload: DashPayload) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                greetingCard(payload)
                overviewSection(payload)
                leadsSection
                monthSection(payload)
                vitrineSection
                nextSessionsSection(payload.nextSessions)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .refreshable { await model.load() }
    }


    // MARK: Vitrine — retorno de quem paga por aparecer

    /// Só aparece com a Vitrine conectada.
    ///
    /// O terapeuta paga a Vitrine todo mês e nunca vê se ela funciona — é o
    /// que explica a diferença de retenção entre quem paga no cartão e quem
    /// paga no pix manual. Mostrar "seu perfil apareceu 47 vezes" aqui, na
    /// primeira tela, é o lugar onde o número tem chance de ser visto.
    @ViewBuilder
    private var vitrineSection: some View {
        if let status = vitrine.status, status.configured, !status.connected {
            if status.inviteDismissed != true {
                ConnectInviteCard(
                    icon: "storefront",
                    titulo: "Conecte sua Vitrine",
                    texto: "Veja aqui quantas pessoas visitaram seu perfil e clicaram no seu WhatsApp, mês a mês.",
                    onDismiss: { await vitrine.dismissInvite() }
                ) {
                    VitrineView()
                }
            }
        } else if let status = vitrine.status, status.connected, status.indisponivel != true,
           let mes = status.mes {
            VStack(alignment: .leading, spacing: 12) {
                Text("SUA VITRINE")
                    .font(Theme.body(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 2)

                NavigationLink {
                    VitrineView()
                } label: {
                    ThemeCard(padding: 16) {
                        VStack(spacing: 14) {
                            HStack(spacing: 0) {
                                vitrineMetric(
                                    valor: mes.visualizacoes,
                                    titulo: "Visualizações",
                                    icone: "eye",
                                    cor: Theme.primary
                                )
                                Divider().frame(height: 38)
                                vitrineMetric(
                                    valor: mes.cliquesWhatsapp,
                                    titulo: "Clicaram no WhatsApp",
                                    icone: "hand.tap",
                                    cor: Color(hex: 0x8FBCA6)
                                )
                            }

                            HStack(spacing: 6) {
                                Text("neste mês")
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                                if let totais = status.impressoesTotais, totais > 0 {
                                    Text("·")
                                        .foregroundStyle(Theme.textSecondary.opacity(0.5))
                                    Text("\(totais) aparições desde o início")
                                        .font(Theme.body(12))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func vitrineMetric(valor: Int, titulo: String, icone: String, cor: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icone)
                .font(.system(size: 15))
                .foregroundStyle(cor)
            Text("\(valor)")
                .font(Theme.serifTitle(26))
                .foregroundStyle(Theme.textPrimary)
            Text(titulo)
                .font(Theme.body(11.5))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Card de saudação (gradiente suave + mini-stats)

    private func greetingCard(_ payload: DashPayload) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Olá, \(payload.greetingName)")
                    .font(Theme.serifTitle(26))
                    .italic()
                    .foregroundStyle(Theme.textPrimary)
                Text("🌿")
                    .font(.system(size: 22))
            }

            Text(AgendaFormat.capitalizedFirst(AgendaFormat.fullDate.string(from: .now)))
                .font(Theme.body(14))
                .foregroundStyle(Theme.textPrimary.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            Text("HOJE")
                .font(Theme.body(10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
                .padding(.top, 12)

            HStack(spacing: 8) {
                miniStat(value: "\(payload.today.total)", label: "Sessões")
                miniStat(value: "\(payload.today.online)", label: "Online")
                miniStat(value: "\(payload.today.toCharge)", label: "A cobrar")
            }

            if payload.today.unreadNotifications > 0 {
                NavigationLink {
                    NotificationsView()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(payload.today.unreadNotifications == 1
                             ? "1 notificação não lida"
                             : "\(payload.today.unreadNotifications) notificações não lidas")
                            .font(Theme.body(13, weight: .medium))
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textPrimary.opacity(0.72))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.pressableSubtle)
                .padding(.top, 8)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(hex: 0xE7F0EA), Color(hex: 0xEDE9F4), Color(hex: 0xE7EDF4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func miniStat(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Theme.money(20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(label.uppercased())
                .font(Theme.body(9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Leads e saldo de créditos (reais)

    @ViewBuilder
    private var leadsSection: some View {
        // Ambiente sem a integração: nada aqui.
        if leads.connection?.configured == false {
            EmptyView()
        } else if let conexao = leads.connection, !conexao.connected {
            // Não conectado: convite com "Agora não", que some de vez (gravado
            // na conta). Conectar continua possível pela tela de leads.
            if conexao.inviteDismissed != true {
                ConnectInviteCard(
                    icon: "tray.full",
                    titulo: "Conecte seus leads",
                    texto: "Receba aqui as pessoas que a Terapia Acolher encaminha para você, acompanhe cada conversa e transforme em paciente sem redigitar.",
                    onDismiss: { await leads.dismissInvite() }
                ) {
                    LeadsListView()
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("LEADS")
                    .font(Theme.body(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 2)

                NavigationLink {
                    LeadsListView()
                } label: {
                    ThemeCard(padding: 16) {
                        HStack(spacing: 14) {
                            Image(systemName: "tray.full.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(Theme.primary)
                                .frame(width: 42, height: 42)
                                .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 12))

                            VStack(alignment: .leading, spacing: 3) {
                                if leads.isConnected {
                                    Text(leads.uncontactedCount == 1
                                         ? "1 lead esperando contato"
                                         : "\(leads.uncontactedCount) leads esperando contato")
                                        .font(Theme.body(15, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                    Text(leads.connection?.indisponivel == true
                                         ? "Sistema de leads indisponível agora"
                                         : leads.lateCount > 0
                                             ? "\(leads.lateCount) há mais de um dia"
                                             : "Nenhum atrasado")
                                        .font(Theme.body(12))
                                        .foregroundStyle(
                                            leads.lateCount > 0 && leads.connection?.indisponivel != true
                                                ? Theme.danger : Theme.textSecondary
                                        )
                                } else {
                                    Text("Conectar meus leads")
                                        .font(Theme.body(15, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1)
                                    Text("Veja aqui quem a Terapia Acolher enviou pra você")
                                        .font(Theme.body(12))
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }
                            }

                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary.opacity(0.5))
                        }
                    }
                }
                .buttonStyle(.pressableSubtle)

                if leads.isConnected, let saldo = leads.connection?.saldo {
                    NavigationLink {
                        LeadsCreditsView()
                    } label: {
                        ThemeCard(padding: 16) {
                            HStack(spacing: 14) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 17))
                                    .foregroundStyle(Theme.warning)
                                    .frame(width: 42, height: 42)
                                    .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: 12))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(saldo == 1 ? "1 crédito restante" : "\(saldo) créditos restantes")
                                        .font(Theme.body(15, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(saldo < LeadCredits.saldoBaixo ? "Saldo baixo — toque para recarregar" : "Saldo em dia")
                                        .font(Theme.body(12))
                                        .foregroundStyle(saldo < LeadCredits.saldoBaixo ? Theme.warning : Theme.textSecondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }

                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
                            }
                        }
                    }
                    .buttonStyle(.pressableSubtle)
                }
            }
        }
    }

    // MARK: Este mês — receita em destaque + faixa compacta
    //
    // A receita saiu do grid 2x2: num card de meia largura o valor encolhia com
    // minimumScaleFactor e ficava ilegível em receitas altas. É a métrica que o
    // terapeuta mais olha, então ganha largura inteira e a tipografia arredondada.

    private func monthSection(_ payload: DashPayload) -> some View {
        let month = payload.month
        return monthSectionContent(month, payload: payload)
    }

    private func monthSectionContent(_ month: DashMonth, payload: DashPayload) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                Text("ESTE MÊS")
                    .font(Theme.body(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                Text("·")
                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
                Text(AgendaFormat.capitalizedFirst(AgendaFormat.monthName.string(from: .now)))
                    .font(Theme.body(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
            .padding(.leading, 2)

            revenueCard(month, history: payload.revenueHistory)
            countsStrip(month)
            if let usage = payload.usage {
                usageCard(usage)
            }
        }
    }

    private func revenueCard(_ month: DashMonth, history: [DashRevenueMonth]?) -> some View {
        ThemeCard(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("RECEITA")
                        .font(Theme.body(11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    variationChip(month.revenueVariationPercent)
                }

                Text(Formatters.brl(month.revenue))
                    .font(Theme.moneyDisplay(34))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(month.attended == 1
                     ? "de 1 sessão atendida"
                     : "de \(month.attended) sessões atendidas")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)

                if let history, history.count > 1 {
                    revenueChart(history)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Chip de variação. Sem mês anterior (0%) não mostra nada: uma seta em 0%
    /// sugere estabilidade onde na verdade não há com o que comparar.
    @ViewBuilder
    private func variationChip(_ percent: Int) -> some View {
        if percent != 0 {
            let positivo = percent > 0
            HStack(spacing: 3) {
                Image(systemName: positivo ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                Text("\(abs(percent))%")
                    .font(Theme.body(12, weight: .semibold))
                Text("vs \(previousMonthName())")
                    .font(Theme.body(12))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(positivo ? Theme.success : Theme.danger)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                (positivo ? Theme.successSoft : Theme.dangerSoft),
                in: Capsule()
            )
        }
    }

    private func countsStrip(_ month: DashMonth) -> some View {
        HStack(spacing: 10) {
            countTile(
                value: "\(month.sessions)",
                label: "Sessões",
                caption: month.sessionsVariationPercent == 0
                    ? "no mês"
                    : variationCaption(month.sessionsVariationPercent),
                captionColor: month.sessionsVariationPercent == 0
                    ? Theme.textSecondary
                    : (month.sessionsVariationPercent < 0 ? Theme.danger : Theme.success)
            )
            countTile(
                value: "\(month.attended)",
                label: "Atendidas",
                caption: "\(month.attendanceRate)% de presença",
                captionColor: Theme.success
            )
            countTile(
                value: "\(month.missed)",
                label: "Faltas",
                caption: missedCaption(month),
                captionColor: month.missed == 0 ? Theme.success : Theme.warning
            )
        }
    }

    /// "nenhuma" quando zerado; senão a taxa, que é o dado acionável — 4 faltas
    /// em 26 sessões e 4 em 6 são situações completamente diferentes.
    private func missedCaption(_ month: DashMonth) -> String {
        guard month.missed > 0 else { return "nenhuma" }
        guard month.sessions > 0 else { return "no mês" }
        return "\(Int((Double(month.missed) / Double(month.sessions) * 100).rounded()))% do mês"
    }

    private func countTile(
        value: String,
        label: String,
        caption: String,
        captionColor: Color
    ) -> some View {
        ThemeCard(padding: 13) {
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(Theme.moneyDisplay(25))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
                    .lineLimit(1)
                Text(caption)
                    .font(Theme.body(10, weight: .medium))
                    .foregroundStyle(captionColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func variationCaption(_ percent: Int, suffix: String = "") -> String {
        let arrow = percent < 0 ? "↓" : "↑"
        return "\(arrow) \(abs(percent))%\(suffix)"
    }

    private func previousMonthName() -> String {
        let previous = AgendaFormat.calendar.date(byAdding: .month, value: -1, to: .now) ?? .now
        return AgendaFormat.monthName.string(from: previous)
    }

    // MARK: Receita dos últimos meses

    /// Seis barras, a do mês atual em destaque.
    private func revenueChart(_ history: [DashRevenueMonth]) -> some View {
        let maior = max(history.map(\.revenue).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Divider().padding(.top, 4)
            Text("ÚLTIMOS 6 MESES")
                .font(Theme.body(10.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(history.enumerated()), id: \.element.id) { i, h in
                    let atual = i == history.count - 1
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(atual ? Theme.primary : Theme.primarySoft)
                            .frame(height: h.revenue > 0 ? max(4, 70 * h.revenue / maior) : 2)
                        Text(UsageFormat.nome(h.month, curto: true))
                            .font(Theme.body(10, weight: atual ? .semibold : .regular))
                            .foregroundStyle(atual ? Theme.textPrimary : Theme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(UsageFormat.nome(h.month)): \(Formatters.brl(h.revenue))")
                }
            }
            .frame(height: 90, alignment: .bottom)
        }
    }

    // MARK: Visão geral

    /// Carteira, semana, dinheiro a entrar e presença — só com backend que manda.
    @ViewBuilder
    private func overviewSection(_ payload: DashPayload) -> some View {
        if payload.patients != nil || payload.week != nil || payload.receivables != nil {
            let decididas = payload.month.attended + payload.month.missed
            VStack(alignment: .leading, spacing: 12) {
                Text("VISÃO GERAL")
                    .font(Theme.body(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 2)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    if let p = payload.patients {
                        overviewTile(
                            icon: "person.2.fill", tint: Theme.primary, soft: Theme.primarySoft,
                            value: "\(p.active)",
                            label: p.active == 1 ? "paciente ativo" : "pacientes ativos",
                            caption: p.newThisMonth > 0
                                ? "+\(p.newThisMonth) \(p.newThisMonth == 1 ? "novo" : "novos") este mês"
                                : "nenhum novo este mês",
                            captionColor: p.newThisMonth > 0 ? Theme.success : Theme.textSecondary
                        ) { PatientsListView() }
                    }
                    if let w = payload.week {
                        overviewTile(
                            icon: "calendar", tint: Color(hex: 0x3E637F), soft: Color(hex: 0xDDEAF3),
                            value: "\(w.sessions)",
                            label: w.sessions == 1 ? "sessão em 7 dias" : "sessões em 7 dias",
                            caption: w.sessions == 0 ? "agenda livre" : "já marcadas",
                            captionColor: Theme.textSecondary
                        ) { AgendaView() }
                    }
                    if let r = payload.receivables {
                        overviewTile(
                            icon: "dollarsign", tint: Theme.warning, soft: Theme.warningSoft,
                            value: Formatters.brl(r.amount),
                            label: "a receber",
                            caption: r.overdueCount > 0
                                ? "\(Formatters.brl(r.overdueAmount)) em atraso"
                                : r.count > 0
                                    ? (r.count == 1 ? "1 cobrança em aberto" : "\(r.count) cobranças em aberto")
                                    : "nada pendente",
                            captionColor: r.overdueCount > 0 ? Theme.danger : Theme.textSecondary
                        ) { FinanceHomeView() }
                    }
                    overviewTile(
                        icon: "checkmark.seal.fill", tint: Theme.success, soft: Theme.successSoft,
                        value: decididas > 0 ? "\(payload.month.attendanceRate)%" : "—",
                        label: "presença no mês",
                        caption: decididas > 0
                            ? "\(payload.month.attended) de \(decididas) sessões"
                            : "aparece após as primeiras sessões",
                        captionColor: Theme.textSecondary
                    ) { AgendaView() }
                }
            }
        }
    }

    private func overviewTile<Destino: View>(
        icon: String, tint: Color, soft: Color,
        value: String, label: String, caption: String, captionColor: Color,
        @ViewBuilder destination: @escaping () -> Destino
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            ThemeCard(padding: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(tint)
                        .frame(width: 34, height: 34)
                        .background(soft, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom, 6)
                    Text(value)
                        .font(Theme.moneyDisplay(22))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(label)
                        .font(Theme.body(12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(caption)
                        .font(Theme.body(10.5))
                        .foregroundStyle(captionColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.pressableSubtle)
    }

    // MARK: Uso da conta no mês

    private func usageCard(_ usage: DashUsage) -> some View {
        NavigationLink {
            UsageView()
        } label: {
            ThemeCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("USO DA CONTA NO MÊS")
                            .font(Theme.body(11, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        HStack(spacing: 3) {
                            Text("Detalhes")
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        }
                        .font(Theme.body(12.5, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        usageItem(usage.whatsapp, "WhatsApp a pacientes", UsageResource.whatsapp)
                        usageItem(usage.transcriptSummaries, "Resumos de transcrição", UsageResource.resumos)
                        usageItem(usage.recordAi, "IA em prontuários", UsageResource.iaRegistros)
                    }
                }
            }
        }
        .buttonStyle(.pressableSubtle)
    }

    private func usageItem(_ valor: Int, _ rotulo: String, _ r: UsageResource) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: r.icon).font(.system(size: 12)).foregroundStyle(r.cor)
                Text("\(valor)")
                    .font(Theme.moneyDisplay(20))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            Text(rotulo)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Próximas sessões

    private func nextSessionsSection(_ sessions: [DashNextSession]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Próximas sessões")
                    .font(Theme.serifTitle(20))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                NavigationLink {
                    DashUpcomingSessionsView()
                } label: {
                    Text("Ver tudo")
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                }
            }
            .padding(.top, 6)

            if sessions.isEmpty {
                EmptyStateView(
                    icon: "calendar",
                    title: "Nenhuma sessão futura",
                    message: "Quando você agendar sessões, elas aparecem aqui."
                )
            } else {
                ForEach(sessions) { session in
                    NavigationLink {
                        AgendaSessionDetailView(sessionId: session.id)
                    } label: {
                        AgendaSessionCardRow(
                            name: session.patient.name,
                            groupName: session.patient.group?.name,
                            groupColorHex: session.patient.group?.color,
                            isOnline: session.isOnline,
                            timeText: AgendaFormat.time.string(from: session.startsAt)
                        )
                    }
                    .buttonStyle(.pressableSubtle)
                }
            }
        }
    }
}

// MARK: - "Ver tudo": próximas sessões agendadas, agrupadas por dia

struct DashUpcomingSessionsView: View {
    @State private var sessions: [AgendaSession] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isRetrying = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(Theme.primary)
            } else if let errorMessage {
                VStack(spacing: 14) {
                    EmptyStateView(icon: "wifi.exclamationmark", title: "Ops, não carregou", message: errorMessage)
                    RetryButton(isLoading: isRetrying) { Task { await load() } }
                }
            } else if sessions.isEmpty {
                EmptyStateView(
                    icon: "calendar",
                    title: "Nenhuma sessão futura",
                    message: "Quando você agendar sessões, elas aparecem aqui."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(AgendaFormat.sections(from: sessions), id: \.day) { section in
                            AgendaDayHeader(day: section.day, count: section.sessions.count)
                                .padding(.top, 10)
                            ForEach(section.sessions) { session in
                                NavigationLink {
                                    AgendaSessionDetailView(sessionId: session.id, preloaded: session)
                                } label: {
                                    AgendaSessionCardRow(session: session)
                                }
                                .buttonStyle(.pressableSubtle)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.bottom, 32)
                }
            }
        }
        .setToolbarTitle("Próximas sessões")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = sessions.isEmpty && errorMessage == nil
        if errorMessage != nil { isRetrying = true }
        errorMessage = nil
        defer { isLoading = false; isRetrying = false }
        do {
            let result: [AgendaSession] = try await APIClient.shared.get("sessions", query: [
                "from": AgendaFormat.isoQuery.string(from: .now),
                "status": "SCHEDULED",
            ])
            sessions = result
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar as sessões."
        }
    }
}


// MARK: - Aviso de perfil incompleto

/// Modal do Início. Não resolve nada aqui de propósito: lista o que falta e
/// leva para o perfil, que é onde os campos moram. Um formulário duplicado
/// dentro do modal viraria uma segunda verdade para manter.
private struct ProfilePendingSheet: View {
    let status: ProfileStatus?
    let onIrParaPerfil: () -> Void
    let onDepois: () -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.warning)
                    .padding(.top, 26)

                VStack(spacing: 6) {
                    Text("Complete seu perfil")
                        .font(Theme.serifTitle(24))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Falta pouco para você receber todos os avisos da plataforma.")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                VStack(spacing: 10) {
                    ForEach(status?.pendenciasVisiveis ?? []) { item in
                        HStack(spacing: 11) {
                            Image(systemName: item.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.warning)
                                .frame(width: 28, height: 28)
                                .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(Theme.body(14, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(item.description)
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 4)

                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    PrimaryButton(title: "Completar agora", icon: "arrow.right") {
                        onIrParaPerfil()
                    }
                    Button("Deixar para depois") { onDepois() }
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.bottom, 18)
            }
            .padding(.horizontal, Theme.screenPadding)
        }
    }
}

// MARK: - Convite de conexão (leads / Vitrine)

/// "Conectar" leva à tela do recurso; "Agora não" some com o convite do Início
/// de vez — gravado na conta, vale no web e em outro aparelho.
private struct ConnectInviteCard<Destino: View>: View {
    let icon: String
    let titulo: String
    let texto: String
    let onDismiss: () async -> Void
    @ViewBuilder let destination: () -> Destino

    @State private var dispensando = false

    var body: some View {
        ThemeCard(padding: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 44, height: 44)
                    .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(titulo)
                        .font(Theme.body(15.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(texto)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        NavigationLink {
                            destination()
                        } label: {
                            HStack(spacing: 5) {
                                Text("Conectar")
                                Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold))
                            }
                            .font(Theme.body(13.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .background(Theme.primary, in: Capsule())
                        }
                        .buttonStyle(.pressable)

                        Button {
                            Haptics.tap()
                            dispensando = true
                            Task {
                                await onDismiss()
                                dispensando = false
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if dispensando {
                                    ProgressView().controlSize(.mini).tint(Theme.textSecondary)
                                }
                                Text("Agora não")
                            }
                            .font(Theme.body(13, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                        }
                        .buttonStyle(.pressableSubtle)
                        .disabled(dispensando)
                    }
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
