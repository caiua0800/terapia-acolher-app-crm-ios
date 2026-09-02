import SwiftUI

/// Destinos do menu lateral.
/// - Atendimento: CORTADO do escopo (veto permanente).
/// - Documentos e Anexos: saíram do menu em 2026-08-30 e passaram a viver dentro da
///   ficha do paciente. Toda rota deles no backend é `/patients/{id}/...` — no menu
///   eram só uma segunda e terceira lista de pacientes, e a ficha, que é onde o
///   terapeuta está quando precisa deles, não tinha entrada nenhuma.
enum MenuDestination: String, CaseIterable, Identifiable {
    case inicio, agenda
    case pacientes, prontuarios, anamneses
    case financeiro, vitrine, leads, creditos
    case configuracoes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inicio: "Início"
        case .agenda: "Agenda"
        case .pacientes: "Pacientes"
        case .prontuarios: "Prontuários"
        case .anamneses: "Anamneses"
        case .financeiro: "Financeiro"
        case .vitrine: "Minha Vitrine"
        case .leads: "Meus leads"
        case .creditos: "Créditos"
        case .configuracoes: "Configurações"
        }
    }

    var icon: String {
        switch self {
        case .inicio: "house"
        case .agenda: "calendar"
        case .pacientes: "person.2"
        case .prontuarios: "doc.text"
        case .anamneses: "pencil.line"
        case .financeiro: "dollarsign"
        case .vitrine: "storefront"
        case .leads: "tray.full"
        case .creditos: "sparkles"
        case .configuracoes: "gearshape"
        }
    }

    /// Seções do menu como no MVP.
    static var sections: [(header: String, items: [MenuDestination])] {
        var todas: [(header: String, items: [MenuDestination])] = [
            ("PRINCIPAL", [.inicio, .agenda]),
        ]
        todas.append((header: "PACIENTES", items: [.pacientes, .prontuarios, .anamneses]))
        todas.append((header: "GESTÃO", items: [.financeiro, .vitrine]))
        // Módulo em demonstração: some do menu inteiro com uma flag.
        if LeadsDemo.enabled {
            todas.append((header: "LEADS", items: [.leads, .creditos]))
        }
        todas.append((header: "CONTA", items: [.configuracoes]))
        return todas
    }
}

/// Shell autenticado: drawer lateral escuro (grafite) + conteúdo.
struct MainShellView: View {
    @State private var selection: MenuDestination = .inicio
    @State private var isMenuOpen = false
    @State private var optIn = PushOptIn.shared
    @Environment(\.openURL) private var openURL
    @State private var deepLink = DeepLink.shared

    var body: some View {
        ZStack(alignment: .leading) {
            NavigationStack {
                destinationView
                    // Sem isto a barra fica em modo "large title" com o título
                    // VAZIO (o título real vai no item .principal) e reserva ~52pt
                    // de espaço morto no topo de todas as seções.
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                withAnimation(.easeOut(duration: 0.22)) { isMenuOpen = true }
                            } label: {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(Theme.textPrimary)
                                    .frame(width: 38, height: 38)
                                    .background(Theme.surface, in: Circle())
                                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                            }
                            .accessibilityIdentifier("menuButton")
                        }
                        ToolbarItem(placement: .principal) {
                            Text(selection.title)
                                .font(Theme.serifTitle(20))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink {
                                NotificationsView()
                            } label: {
                                Image(systemName: "bell")
                                    .foregroundStyle(Theme.textPrimary)
                                    .frame(width: 38, height: 38)
                                    .background(Theme.surface, in: Circle())
                                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                            }
                            .accessibilityIdentifier("bellButton")
                        }
                    }
            }

            if isMenuOpen {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeIn(duration: 0.18)) { isMenuOpen = false }
                    }
                SideMenuView(selection: $selection, isOpen: $isMenuOpen)
                    .transition(.move(edge: .leading))
            }

            // Aviso de conexão fica AQUI, na casca, não em cada tela: o fato é
            // do aparelho, não da tela. Repetido em 27 telas seria ruído e
            // manutenção duplicada.
            OfflineBanner()
        }
        // Notificação tocada enquanto o app está em outra seção: leva pra
        // seção certa antes de a tela de destino tentar se abrir.
        // Todas as seções que o painel de suporte oferece precisam existir
        // aqui. Antes só "agenda" e "financeiro" eram tratadas, então uma
        // notificação com destino "Minha Vitrine" abria o app e parava.
        .onChange(of: deepLink.pendingSection) { _, secao in
            guard let secao else { return }
            switch secao {
            case "inicio": selection = .inicio
            case "agenda": selection = .agenda
            case "pacientes": selection = .pacientes
            case "prontuarios": selection = .prontuarios
            case "anamneses": selection = .anamneses
            case "financeiro": selection = .financeiro
            case "vitrine": selection = .vitrine
            case "configuracoes": selection = .configuracoes
            default: break
            }
            deepLink.pendingSection = nil
        }
        .onChange(of: deepLink.externalURL) { _, url in
            guard let url else { return }
            deepLink.externalURL = nil
            openURL(url)
        }
        .task {
            await PushManager.shared.refreshAuthorization()
            // Só convida depois de o terapeuta ter usado o app. O alerta do
            // sistema só pode ser mostrado UMA vez — pedir na primeira tela é
            // o jeito mais rápido de levar um "não" definitivo.
            optIn.registrarAbertura()

            // Dois sheets na mesma janela se derrubam: o SwiftUI apresenta um
            // e fecha o outro na hora. O aviso de perfil incompleto (Início)
            // tem prioridade — sem e-mail e telefone confirmados o terapeuta
            // não recebe nada, então convidar para push antes disso é pedir
            // permissão para um canal que ainda não tem o que entregar.
            if ProfileStatusStore.shared.status == nil {
                await ProfileStatusStore.shared.refresh()
            }
            let temPendencia = ProfileStatusStore.shared.status?.temPendencia ?? false
            if !temPendencia || ProfileStatusStore.shared.dispensadoNestaSessao {
                optIn.avaliar(status: PushManager.shared.authorization)
            }
        }
        .sheet(isPresented: $optIn.mostrando) {
            PushOptInSheet {
                optIn.registrarDecisao()
            }
            .presentationDetents([.large])
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch selection {
        case .inicio: DashboardView()
        case .agenda: AgendaView()
        case .pacientes: PatientsListView()
        case .prontuarios: RecordsHomeView(kind: .record)
        case .anamneses: RecordsHomeView(kind: .anamnesis)
        case .financeiro: FinanceHomeView()
        case .vitrine: VitrineView()
        case .leads: LeadsListView()
        case .creditos: LeadsCreditsView()
        case .configuracoes: SettingsHomeView()
        }
    }
}

/// Drawer escuro fiel ao MVP (grafite, item ativo em verde).
struct SideMenuView: View {
    @Binding var selection: MenuDestination
    @Binding var isOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image("LogoAcolher")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Terapia Acolher")
                        .font(Theme.serifTitle(18))
                        .foregroundStyle(.white)
                    Text("PAINEL DA TERAPEUTA")
                        .font(Theme.body(10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .tracking(1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 28)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(MenuDestination.sections, id: \.header) { section in
                        Text(section.header)
                            .font(Theme.body(11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                            .tracking(1.2)
                            .padding(.horizontal, 20)
                            .padding(.top, 18)
                            .padding(.bottom, 6)
                        ForEach(section.items) { item in
                            menuRow(item)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 290)
        .frame(maxHeight: .infinity)
        // fundo estende até as bordas; conteúdo respeita a safe area (não colide com o relógio)
        .background(Theme.ink.ignoresSafeArea())
    }

    private func menuRow(_ item: MenuDestination) -> some View {
        Button {
            selection = item
            withAnimation(.easeIn(duration: 0.18)) { isOpen = false }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 16))
                    .frame(width: 22)
                Text(item.title)
                    .font(Theme.body(15, weight: selection == item ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(selection == item ? Color.white : Color.white.opacity(0.75))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                selection == item ? Theme.primary : Color.clear,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .padding(.horizontal, 10)
        }
    }
}
