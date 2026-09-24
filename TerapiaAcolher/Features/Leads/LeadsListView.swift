import SwiftUI

/// Meus leads — resumo do funil, busca, e duas visões: Quadro (colunas por
/// etapa, roláveis na horizontal) e Lista (com chips de etapa).
///
/// Os leads vêm do sistema de leads da Terapia Acolher (onde caem os pacientes
/// do ManyChat), lidos em nome do terapeuta depois que ele conecta a conta —
/// mesmo aperto de mão da Vitrine, sem copiar chave. Mesma tela do web
/// (`web-app/app/(app)/leads/leads.tsx`), adaptada ao toque: no celular mudar
/// de etapa é por menu, não arrastando entre colunas.
struct LeadsListView: View {
    @State private var store = LeadsStore.shared
    @State private var showDisconnect = false
    @AppStorage("leads.visao") private var visaoSalva = Visao.lista.rawValue
    @State private var busca = ""
    @State private var paraQuem: LeadTherapyFor?
    @State private var ordem: Ordem = .recentes
    @State private var filtro: Filtro = .abertos
    @State private var movendo: String?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    enum Visao: String { case quadro, lista }

    enum Ordem: String, CaseIterable, Identifiable {
        case recentes, antigos, nome
        var id: Self { self }
        var label: String {
            switch self {
            case .recentes: "Mais recentes"
            case .antigos: "Mais antigos"
            case .nome: "Nome (A–Z)"
            }
        }
    }

    enum Filtro: Hashable {
        case abertos, atrasados, etapa(LeadStatus), todos

        func matches(_ lead: Lead) -> Bool {
            switch self {
            case .abertos: lead.status.isOpen
            case .atrasados: lead.sla == .late
            case .etapa(let s): lead.status == s
            case .todos: true
            }
        }
    }

    private var visao: Visao { Visao(rawValue: visaoSalva) ?? .lista }

    /// Busca, "para quem" e ordem valem nas duas visões; o filtro de etapa só
    /// na lista (no quadro as etapas já são as colunas).
    private var visiveis: [Lead] {
        store.leads
            .filter { $0.matches(search: busca) && (paraQuem == nil || $0.therapyFor == paraQuem) }
            .sorted {
                switch ordem {
                case .recentes: $0.receivedAt > $1.receivedAt
                case .antigos: $0.receivedAt < $1.receivedAt
                case .nome: $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content
        }
        .setToolbarTitle("Meus leads")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        // O sistema de leads não avisa o CRM quando chega lead novo: com a tela
        // aberta, pergunta de novo a cada minuto.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { break }
                if store.isConnected { await store.load() }
            }
        }
        // O consentimento acontece no NAVEGADOR: quando o app volta a ficar
        // ativo, recarrega para refletir a conexão sem precisar puxar a tela.
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
            ScrollView {
                VStack(spacing: 12) {
                    SkeletonBlock(height: 90)
                    SkeletonBlock(height: 90)
                    SkeletonBlock(height: 220)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
            }
        } else if let erro = store.errorMessage, store.connection == nil {
            ErrorRetryView(message: erro) { Task { await store.load() } }
        } else if let conexao = store.connection, !conexao.configured {
            indisponivelCard
        } else if !store.isConnected {
            convite
        } else {
            painel
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
                        .font(Theme.serifTitle(23))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(store.connection?.revogada == true
                         ? "A conexão com sua conta de leads foi desfeita. Conecte de novo para voltar a ver os leads por aqui."
                         : "Veja quem a Terapia Acolher encaminhou para você, acompanhe cada conversa num quadro e transforme em paciente sem redigitar nada.")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 12) {
                    passo(1, "Você entra no portal da Terapia Acolher com o login de sempre.")
                    passo(2, "Confirma a conexão — sem copiar chave nenhuma.")
                    passo(3, "Volta para cá com todos os seus leads organizados.")
                }
                .padding(.vertical, 4)

                PrimaryButton(
                    title: "Conectar meus leads",
                    icon: "arrow.up.right",
                    isLoading: store.isWorking
                ) {
                    Task {
                        if let url = await store.connectURL() { openURL(url) }
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 12)
        }
    }

    private func passo(_ n: Int, _ texto: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(Theme.body(12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Theme.ink, in: Circle())
            Text(texto)
                .font(Theme.body(14))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
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

    private var painel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.connection?.indisponivel == true {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warning)
                        Text("Não conseguimos falar com o sistema de leads agora. Sua conta continua conectada — tente atualizar em instantes.")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                }

                cabecalho
                indicadores
                funil
                if store.lateCount > 0 { avisoAtrasados }
                ferramentas

                if store.leads.isEmpty {
                    ThemeCard {
                        EmptyStateView(
                            icon: "tray",
                            title: "Nenhum lead ainda",
                            message: "Quando a Terapia Acolher enviar um paciente para você, ele aparece aqui."
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                } else if visao == .quadro {
                    quadro
                } else {
                    lista
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 32)
        }
        .refreshable { await store.load() }
    }

    // MARK: Cabeçalho e resumo

    private var cabecalho: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(store.leads.count) \(store.leads.count == 1 ? "pessoa encaminhada" : "pessoas encaminhadas")")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                if let ultimo = store.connection?.ultimoRecebidoEm {
                    Text("último em \(PatientFormat.fullDate.string(from: ultimo))")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            if let saldo = store.connection?.saldo {
                NavigationLink {
                    LeadsCreditsView()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.warning)
                        Text("Saldo").foregroundStyle(Theme.textSecondary)
                        Text("\(saldo)").fontWeight(.semibold).foregroundStyle(Theme.textPrimary).monospacedDigit()
                        Text("Comprar").fontWeight(.semibold).foregroundStyle(Theme.primary)
                    }
                    .font(Theme.body(13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, Theme.screenPadding)
    }

    private var indicadores: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            indicador(
                "A CONTACTAR", "\(store.uncontactedCount)", Theme.primary,
                store.lateCount > 0 ? "\(store.lateCount) há mais de 24h" : store.uncontactedCount > 0 ? "todos no prazo" : "ninguém esperando",
                store.lateCount > 0 ? Theme.danger : Theme.textSecondary
            )
            indicador(
                "EM CONVERSA", "\(store.inConversationCount)", LeadStatus.negociando.tint,
                "\(store.count(.tentandoContato)) tentando · \(store.count(.negociando)) negociando", Theme.textSecondary
            )
            indicador(
                "AGENDADOS", "\(store.count(.agendado))", Theme.success,
                store.becamePatientCount > 0
                    ? "\(store.becamePatientCount) já \(store.becamePatientCount == 1 ? "é paciente" : "são pacientes")"
                    : "nenhum virou paciente ainda",
                Theme.textSecondary
            )
            indicador(
                "CONVERSÃO", store.conversionRate.map { "\($0)%" } ?? "—", Theme.ink,
                store.conversionRate != nil ? "dos leads já decididos" : "aparece quando houver decididos",
                Theme.textSecondary
            )
        }
        .padding(.horizontal, Theme.screenPadding)
    }

    private func indicador(_ rotulo: String, _ valor: String, _ cor: Color, _ legenda: String, _ corLegenda: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rotulo)
                .font(Theme.body(10.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
            Text(valor)
                .font(Theme.moneyDisplay(26))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(legenda)
                .font(Theme.body(11.5, weight: corLegenda == Theme.danger ? .semibold : .regular))
                .foregroundStyle(corLegenda)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(cor).frame(height: 3) }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.border, lineWidth: 1))
    }

    @ViewBuilder
    private var funil: some View {
        if !store.leads.isEmpty {
            ThemeCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            ForEach(LeadStatus.allCases) { s in
                                let n = store.count(s)
                                if n > 0 {
                                    Rectangle()
                                        .fill(s.tint)
                                        .frame(width: geo.size.width * CGFloat(n) / CGFloat(max(store.leads.count, 1)))
                                }
                            }
                        }
                    }
                    .frame(height: 8)
                    .background(Theme.border.opacity(0.6))
                    .clipShape(Capsule())

                    FlowLayout(spacing: 12) {
                        ForEach(LeadStatus.allCases) { s in
                            HStack(spacing: 5) {
                                Circle().fill(s.tint).frame(width: 7, height: 7)
                                Text(s.label).foregroundStyle(Theme.textSecondary)
                                Text("\(store.count(s))").fontWeight(.semibold).foregroundStyle(Theme.textPrimary)
                            }
                            .font(Theme.body(11.5))
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
        }
    }

    private var avisoAtrasados: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                visaoSalva = Visao.lista.rawValue
                filtro = .atrasados
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.badge.exclamationmark.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.danger, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.lateCount == 1 ? "1 lead esperando há mais de 24h" : "\(store.lateCount) leads esperando há mais de 24h")
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("O primeiro contato rápido é o que mais converte.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.danger)
            }
            .padding(14)
            .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.danger.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.pressableSubtle)
        .padding(.horizontal, Theme.screenPadding)
    }

    // MARK: Ferramentas

    private var ferramentas: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.textSecondary)
                TextField("Buscar por nome, telefone ou motivo", text: $busca)
                    .font(Theme.body(15))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !busca.isEmpty {
                    Button { busca = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))

            HStack(spacing: 8) {
                Menu {
                    Picker("Para quem", selection: $paraQuem) {
                        Text("Todos").tag(LeadTherapyFor?.none)
                        ForEach([LeadTherapyFor.normal, .casal, .infantil, .outraPessoa], id: \.self) { p in
                            Text(p.label).tag(LeadTherapyFor?.some(p))
                        }
                    }
                } label: {
                    menuLabel(paraQuem.map { "Para: \($0.label)" } ?? "Para quem: todos", ativo: paraQuem != nil)
                }
                Menu {
                    Picker("Ordenar", selection: $ordem) {
                        ForEach(Ordem.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    menuLabel(ordem.label, ativo: ordem != .recentes)
                }
                Spacer(minLength: 0)
                Picker("Visão", selection: Binding(
                    get: { visao },
                    set: { novo in
                        Haptics.tap()
                        withAnimation(.easeInOut(duration: 0.2)) { visaoSalva = novo.rawValue }
                    }
                )) {
                    Image(systemName: "list.bullet").tag(Visao.lista)
                    Image(systemName: "rectangle.split.3x1").tag(Visao.quadro)
                }
                .pickerStyle(.segmented)
                .frame(width: 104)
                .accessibilityLabel("Visão: lista ou quadro")
            }
        }
        .padding(.horizontal, Theme.screenPadding)
    }

    private func menuLabel(_ texto: String, ativo: Bool) -> some View {
        HStack(spacing: 4) {
            Text(texto).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
        }
        .font(Theme.body(12.5, weight: ativo ? .semibold : .regular))
        .foregroundStyle(ativo ? Theme.primary : Theme.textPrimary)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(ativo ? Theme.primarySoft : Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(ativo ? Color.clear : Theme.border, lineWidth: 1))
    }

    // MARK: Lista

    private var naLista: [Lead] { visiveis.filter { filtro.matches($0) } }

    private var lista: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("Em aberto", .abertos, store.openCount)
                    chip("Atrasados", .atrasados, store.lateCount)
                    ForEach(LeadStatus.allCases) { s in chip(s.label, .etapa(s), store.count(s)) }
                    chip("Todos", .todos, store.leads.count)
                }
                .padding(.horizontal, Theme.screenPadding)
            }

            if naLista.isEmpty {
                ThemeCard {
                    EmptyStateView(
                        icon: "tray",
                        title: "Nada por aqui",
                        message: !busca.isEmpty || paraQuem != nil
                            ? "Nenhum lead com essa busca."
                            : filtro == .atrasados
                                ? "Nenhum lead esperando há mais de um dia. Bom trabalho."
                                : filtro == .etapa(.novo) ? "Você já falou com todo mundo que chegou." : "Nenhum lead neste filtro."
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .padding(.horizontal, Theme.screenPadding)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(naLista) { lead in
                        NavigationLink {
                            LeadDetailView(leadId: lead.id)
                        } label: {
                            LeadCard(lead: lead, isMoving: movendo == lead.id)
                        }
                        .buttonStyle(.pressableSubtle)
                        .contextMenu { menuDeEtapa(lead) }
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
            }
        }
    }

    private func chip(_ rotulo: String, _ f: Filtro, _ n: Int) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.easeInOut(duration: 0.18)) { filtro = f }
        } label: {
            HStack(spacing: 5) {
                Text(rotulo)
                Text("\(n)").foregroundStyle(filtro == f ? Color.white.opacity(0.65) : Theme.textSecondary)
            }
            .font(Theme.body(13.5, weight: filtro == f ? .semibold : .regular))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(filtro == f ? Theme.ink : Theme.surface, in: Capsule())
            .foregroundStyle(filtro == f ? Color.white : Theme.textPrimary)
            .overlay(Capsule().stroke(Theme.border, lineWidth: filtro == f ? 0 : 1))
        }
        .buttonStyle(.pressable)
    }

    // MARK: Quadro

    private var quadro: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(LeadStatus.allCases) { etapa in
                    coluna(etapa)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 4)
        }
        .scrollTargetBehavior(.viewAligned)
    }

    private func coluna(_ etapa: LeadStatus) -> some View {
        let daColuna = visiveis.filter { $0.status == etapa }
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Circle().fill(etapa.tint).frame(width: 9, height: 9)
                    Text(etapa.label)
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(daColuna.count)")
                        .font(Theme.body(12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.surface, in: Capsule())
                }
                Text(etapa.hint)
                    .font(Theme.body(11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)

            if daColuna.isEmpty {
                Text("Nenhum lead nesta etapa")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 26)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [5]))
                    )
            } else {
                ForEach(daColuna) { lead in
                    NavigationLink {
                        LeadDetailView(leadId: lead.id)
                    } label: {
                        CartaoDoQuadro(lead: lead, isMoving: movendo == lead.id) { menuDeEtapa(lead) }
                    }
                    .buttonStyle(.pressableSubtle)
                    .contextMenu { menuDeEtapa(lead) }
                }
            }
        }
        .padding(10)
        .frame(width: 286, alignment: .top)
        .background(Color(hex: 0xF3EFE7), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    /// "Mover para…" — no celular é o que substitui arrastar entre colunas.
    @ViewBuilder
    private func menuDeEtapa(_ lead: Lead) -> some View {
        Section("Mover para") {
            ForEach(LeadStatus.allCases.filter { $0 != lead.status }) { etapa in
                Button {
                    mover(lead, para: etapa)
                } label: {
                    Label(etapa.label, systemImage: etapa.icon)
                }
            }
        }
    }

    private func mover(_ lead: Lead, para etapa: LeadStatus) {
        Haptics.tap()
        movendo = lead.id
        Task {
            await store.updateStatus(lead.id, to: etapa)
            movendo = nil
            if store.lead(id: lead.id)?.status == etapa { Haptics.success() }
        }
    }
}

// MARK: - Card do lead (lista)

struct LeadCard: View {
    let lead: Lead
    var isMoving = false

    var body: some View {
        ThemeCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    InitialAvatar(name: lead.name, colorHex: nil, size: 42)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(lead.name)
                                .font(Theme.body(15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            if lead.convertedPatientId != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.success)
                            }
                        }
                        HStack(spacing: 6) {
                            let (cor, fundo) = LeadStyle.colors(for: lead.status)
                            StatusBadge(label: lead.status.shortLabel, color: cor, background: fundo)
                            Text(lead.therapyFor.label)
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 6)
                    if isMoving {
                        ProgressView().controlSize(.small).tint(Theme.primary)
                    } else {
                        LeadSLAChip(lead: lead)
                    }
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
}

// MARK: - Cartão do quadro

private struct CartaoDoQuadro<Menu: View>: View {
    let lead: Lead
    let isMoving: Bool
    @ViewBuilder let menu: () -> Menu

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                InitialAvatar(name: lead.name, colorHex: nil, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(lead.name)
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    LeadSLAChip(lead: lead)
                }
                Spacer(minLength: 4)
                if isMoving {
                    ProgressView().controlSize(.small).tint(Theme.primary)
                } else {
                    SwiftUI.Menu { menu() } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Theme.background, in: Circle())
                    }
                    .accessibilityLabel("Mover \(lead.name) de etapa")
                }
            }
            if !lead.reason.isEmpty {
                Text(lead.reason)
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 5) {
                etiqueta(lead.therapyFor.label)
                if lead.shift != .qualquer { etiqueta(lead.shift.label) }
                if lead.convertedPatientId != nil {
                    Label("Paciente", systemImage: "checkmark")
                        .font(Theme.body(10.5, weight: .semibold))
                        .foregroundStyle(Theme.success)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.successSoft, in: Capsule())
                }
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(lead.sla == .late ? Theme.danger.opacity(0.35) : Theme.border, lineWidth: 1)
        )
        .opacity(lead.status == .naoConverteu ? 0.75 : 1)
    }

    private func etiqueta(_ t: String) -> some View {
        Text(t)
            .font(Theme.body(10.5, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(hex: 0xF1EDE4), in: Capsule())
    }
}

/// Tempo desde a chegada. Vermelho só quando ninguém falou com o lead —
/// depois do contato o relógio deixa de ser cobrança.
struct LeadSLAChip: View {
    let lead: Lead

    var body: some View {
        let cor: Color = switch lead.sla {
        case .late: Theme.danger
        case .warning: Theme.warning
        case .fresh: Theme.success
        case .none: Theme.textSecondary
        }
        HStack(spacing: 3) {
            if lead.sla == .late {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 10, weight: .bold))
            } else if lead.sla == .fresh {
                Circle().fill(Theme.success).frame(width: 6, height: 6)
            }
            Text(lead.elapsedLabel)
                .font(Theme.body(11, weight: lead.sla == .none ? .regular : .semibold))
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
        case .negociando: (Color(hex: 0x3E637F), Color(hex: 0xDDEAF3))
        case .agendado: (Theme.success, Theme.successSoft)
        case .naoConverteu: (Theme.textSecondary, Theme.border.opacity(0.5))
        }
    }
}
