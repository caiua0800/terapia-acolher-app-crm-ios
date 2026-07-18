import SwiftUI

/// Destinos do menu lateral (fiel ao MVP — módulo Atendimento foi CORTADO do escopo).
enum MenuDestination: String, CaseIterable, Identifiable {
    case inicio, agenda
    case pacientes, prontuarios, anamneses
    case financeiro, documentos, arquivos
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
        case .documentos: "Documentos"
        case .arquivos: "Arquivos"
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
        case .documentos: "doc"
        case .arquivos: "folder"
        case .configuracoes: "gearshape"
        }
    }

    /// Seções do menu como no MVP.
    static let sections: [(header: String, items: [MenuDestination])] = [
        ("PRINCIPAL", [.inicio, .agenda]),
        ("PACIENTES", [.pacientes, .prontuarios, .anamneses]),
        ("GESTÃO", [.financeiro, .documentos, .arquivos]),
        ("CONTA", [.configuracoes]),
    ]
}

/// Shell autenticado: drawer lateral escuro (grafite) + conteúdo.
struct MainShellView: View {
    @State private var selection: MenuDestination = .inicio
    @State private var isMenuOpen = false

    var body: some View {
        ZStack(alignment: .leading) {
            NavigationStack {
                destinationView
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
        case .documentos: DocumentsHomeView()
        case .arquivos: FilesHomeView()
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
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Theme.primary, Color(hex: 0xB9A6D9)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
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
