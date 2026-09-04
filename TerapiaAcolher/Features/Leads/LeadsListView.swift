import SwiftUI

/// Lista de leads recebidos.
///
/// Os leads vêm do sistema de leads da Terapia Acolher (onde caem os pacientes
/// do ManyChat), lidos em nome do terapeuta depois que ele conecta a conta —
/// mesmo aperto de mão da Vitrine, sem copiar chave.
struct LeadsListView: View {
    @State private var store = LeadsStore.shared
    @State private var filter: Filter = .abertos
    @State private var showDisconnect = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    enum Filter: CaseIterable, Identifiable {
        case abertos, novos, atrasados, todos, convertidos

        var id: Self { self }

        var label: String {
            switch self {
            case .abertos: "Em aberto"
            case .novos: "Não contactados"
            case .atrasados: "Atrasados"
            case .convertidos: "Agendados"
            case .todos: "Todos"
            }
        }

        func matches(_ lead: Lead) -> Bool {
            switch self {
            case .abertos: lead.status.isOpen
            case .novos: lead.status == .novo
            case .atrasados: lead.sla == .late
            case .convertidos: lead.status == .agendado
            case .todos: true
            }
        }
    }

    private var filtered: [Lead] {
        store.leads
            .filter { filter.matches($0) }
            .sorted { $0.receivedAt > $1.receivedAt }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content
        }
        .setToolbarTitle("Meus leads")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        // O consentimento acontece no NAVEGADOR: quando o app volta a ficar
        // ativo, recarrega para refletir a conexão sem o terapeuta ter que
        // puxar a tela.
        .onChange(of: scenePhase) { _, fase in
            if fase == .active { Task { await store.load() } }
        }
        .alert("Ops", isPresented: $store.showAlerta) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.alerta ?? "Algo deu errado.")
        }
        .confirmationDialog(
            "Desconectar seus leads?",
            isPresented: $showDisconnect,
            titleVisibility: .visible
        ) {
            Button("Desconectar", role: .destructive) {
                Task { await store.disconnect() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Seus leads continuam no portal da Terapia Acolher. Você só deixa de vê-los aqui.")
        }
        .toolbar {
            if store.isConnected {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Desconectar conta de leads", role: .destructive) {
                            showDisconnect = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading {
            ProgressView().tint(Theme.primary)
        } else if let erro = store.errorMessage, store.connection == nil {
            ErrorRetryView(message: erro) { Task { await store.load() } }
        } else if let conexao = store.connection, !conexao.configured {
            indisponivelCard
        } else if !store.isConnected {
            convite
        } else {
            lista
        }
    }

    // MARK: Não conectado

    private var convite: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 68, height: 68)
                        .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 18))

                    Text("Seus leads aqui dentro")
                        .font(Theme.serifTitle(21))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(store.connection?.revogada == true
                         ? "A conexão com sua conta de leads foi desfeita. Conecte de novo para voltar a ver os leads por aqui."
                         : "Conecte sua conta do portal da Terapia Acolher para ver os leads que você recebeu, chamar no WhatsApp e transformar em paciente sem redigitar nada.")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 20)

                PrimaryButton(
                    title: "Conectar meus leads",
                    icon: "arrow.up.right",
                    isLoading: store.isWorking
                ) {
                    Task {
                        if let url = await store.connectURL() { openURL(url) }
                    }
                }

                Text("Você entra no portal com o mesmo login de sempre, confirma, e volta pra cá. Não precisa copiar nada.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 12)
        }
    }

    private var indisponivelCard: some View {
        VStack {
            ThemeCard {
                Text("A integração com o sistema de leads ainda não está habilitada neste ambiente.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 12)
    }

    // MARK: Conectado

    private var lista: some View {
        VStack(spacing: 0) {
            if store.connection?.indisponivel == true {
                ThemeCard {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Theme.warning)
                        Text("Não conseguimos falar com o sistema de leads agora. Sua conta continua conectada.")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
            }

            header
            chips

            if filtered.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "tray",
                    title: store.leads.isEmpty ? "Nenhum lead ainda" : "Nada por aqui",
                    message: emptyMessage
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { lead in
                            NavigationLink {
                                LeadDetailView(leadId: lead.id)
                            } label: {
                                LeadCard(lead: lead)
                            }
                            .buttonStyle(.pressableSubtle)
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.bottom, 28)
                }
                .refreshable { await store.load() }
            }
        }
    }

    private var emptyMessage: String {
        if store.leads.isEmpty {
            return "Quando a Terapia Acolher enviar um paciente para você, ele aparece aqui."
        }
        switch filter {
        case .atrasados: return "Nenhum lead esperando há mais de um dia. Bom trabalho."
        case .novos: return "Você já falou com todo mundo que chegou."
        default: return "Nenhum lead neste filtro."
        }
    }

    // MARK: Cabeçalho

    private var header: some View {
        HStack(spacing: 10) {
            headerTile(
                value: "\(store.uncontactedCount)",
                label: "a contactar",
                color: store.uncontactedCount > 0 ? Theme.primary : Theme.textSecondary
            )
            headerTile(
                value: "\(store.lateCount)",
                label: store.lateCount == 1 ? "atrasado" : "atrasados",
                color: store.lateCount > 0 ? Theme.danger : Theme.textSecondary
            )
            headerTile(
                value: store.conversionRate.map { "\($0)%" } ?? "—",
                label: "conversão",
                color: Theme.success
            )
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 8)
    }

    private func headerTile(value: String, label: String, color: Color) -> some View {
        ThemeCard(padding: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(Theme.moneyDisplay(23))
                    .monospacedDigit()
                    .foregroundStyle(color)
                Text(label)
                    .font(Theme.body(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases) { opcao in
                    FilterChip(label: opcao.label, isSelected: filter == opcao) {
                        Haptics.tap()
                        withAnimation(.easeInOut(duration: 0.2)) { filter = opcao }
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Card do lead

struct LeadCard: View {
    let lead: Lead

    var body: some View {
        ThemeCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    InitialAvatar(name: lead.name, colorHex: nil, size: 42)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(lead.name)
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            statusBadge
                            Text(lead.therapyFor.label)
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 6)
                    slaChip
                }

                if !lead.reason.isEmpty {
                    Text(lead.reason)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var statusBadge: some View {
        let (cor, fundo) = LeadStyle.colors(for: lead.status)
        return StatusBadge(label: lead.status.shortLabel, color: cor, background: fundo)
    }

    /// Tempo desde a chegada. Vermelho só quando ninguém falou com o lead —
    /// depois do contato o relógio deixa de ser cobrança.
    private var slaChip: some View {
        let cor: Color = switch lead.sla {
        case .late: Theme.danger
        case .warning: Theme.warning
        case .fresh: Theme.success
        case .none: Theme.textSecondary
        }
        return HStack(spacing: 3) {
            if lead.sla == .late {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 10, weight: .bold))
            }
            Text(lead.elapsedLabel)
                .font(Theme.body(11, weight: .semibold))
        }
        .foregroundStyle(cor)
        .lineLimit(1)
        .fixedSize()
    }
}

enum LeadStyle {
    static func colors(for status: LeadStatus) -> (Color, Color) {
        switch status {
        case .novo: (Theme.primary, Theme.primarySoft)
        case .tentandoContato: (Theme.warning, Theme.warningSoft)
        case .negociando: (Color(hex: 0x7FA8C9), Color(hex: 0xDDEAF3))
        case .agendado: (Theme.success, Theme.successSoft)
        case .naoConverteu: (Theme.textSecondary, Theme.border.opacity(0.5))
        }
    }
}
