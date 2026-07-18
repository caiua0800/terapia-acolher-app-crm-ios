import Observation
import SwiftUI

/// Raiz de Configurações — fiel ao MVP: card do perfil no topo,
/// seções CONSULTÓRIO / TEMPLATES / INTEGRAÇÕES / CONTA com contadores.
struct SettingsHomeView: View {
    @State private var viewModel = SettingsHomeViewModel()
    @State private var showLogoutConfirm = false

    private var session: SessionStore { .shared }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    profileCard
                    consultorioSection
                    templatesSection
                    integracoesSection
                    contaSection
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 16)
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .alert("Ops", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Algo deu errado.")
        }
        .confirmationDialog(
            "Sair da conta?",
            isPresented: $showLogoutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sair", role: .destructive) {
                Task { await SessionStore.shared.logout() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Você vai precisar entrar de novo com e-mail e senha.")
        }
    }

    // MARK: - Perfil

    private var displayName: String {
        let name = session.user?.name ?? ""
        return name.lowercased().hasPrefix("dr") ? name : "Dra. \(name)"
    }

    private var profileSubtitle: String {
        let parts = [session.user?.specialty, session.user?.professionalRegistration]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Complete seu perfil profissional" : parts.joined(separator: " · ")
    }

    private var profileCard: some View {
        NavigationLink {
            SetProfileView()
        } label: {
            ThemeCard {
                HStack(spacing: 14) {
                    InitialAvatar(name: session.user?.name ?? "?", size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayName)
                            .font(Theme.serifTitle(20))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(profileSubtitle)
                            .font(Theme.body(13, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.6))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Seções

    private var consultorioSection: some View {
        VStack(spacing: 8) {
            SetSectionHeader(title: "Consultório")
            ThemeCard(padding: 0) {
                VStack(spacing: 0) {
                    NavigationLink {
                        SetOfficeView()
                    } label: {
                        SetRow(icon: "house", iconColor: Theme.primary, title: "Meu consultório")
                    }
                    Divider().padding(.leading, 62)
                    NavigationLink {
                        SetGroupsView(onChanged: { Task { await viewModel.load() } })
                    } label: {
                        SetRow(
                            icon: "circle.grid.2x2",
                            iconColor: Color(hex: 0xB9A6D9),
                            title: "Grupos de pacientes",
                            trailing: viewModel.groupCount.map(String.init)
                        )
                    }
                    Divider().padding(.leading, 62)
                    NavigationLink {
                        SetAgendaView()
                    } label: {
                        SetRow(icon: "calendar", iconColor: Color(hex: 0xE8B98A), title: "Configurações da agenda")
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var templatesSection: some View {
        VStack(spacing: 8) {
            SetSectionHeader(title: "Templates")
            ThemeCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(SetTemplateType.allCases.enumerated()), id: \.element) { index, type in
                        if index > 0 { Divider().padding(.leading, 62) }
                        NavigationLink {
                            SetTemplatesListView(type: type, onChanged: { Task { await viewModel.load() } })
                        } label: {
                            SetRow(
                                icon: type.icon,
                                iconColor: type.tint,
                                title: type.rowTitle,
                                trailing: viewModel.templateCounts[type].map(String.init)
                            )
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var integracoesSection: some View {
        VStack(spacing: 8) {
            SetSectionHeader(title: "Integrações")
            ThemeCard(padding: 0) {
                VStack(spacing: 0) {
                    NavigationLink {
                        SetGoogleView(onChanged: { Task { await viewModel.load() } })
                    } label: {
                        SetRow(
                            icon: "video",
                            iconColor: Color(hex: 0x7FA8C9),
                            title: "Google Calendar · Meet",
                            trailing: viewModel.googleConnected.map { $0 ? "Conectado" : "Desconectado" }
                        )
                    }
                    Divider().padding(.leading, 62)
                    // A carteira Asaas mora no módulo Financeiro — aqui é só orientação.
                    SetRow(
                        icon: "creditcard",
                        iconColor: Theme.warning,
                        title: "Asaas · Carteira",
                        subtitle: "Gerencie cobranças e carteira no módulo Financeiro",
                        showChevron: false
                    )
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var contaSection: some View {
        VStack(spacing: 8) {
            SetSectionHeader(title: "Conta")
            ThemeCard(padding: 0) {
                VStack(spacing: 0) {
                    NavigationLink {
                        SetChangePasswordView()
                    } label: {
                        SetRow(icon: "lock", iconColor: Theme.textSecondary, title: "Trocar senha")
                    }
                    Divider().padding(.leading, 62)
                    Button {
                        showLogoutConfirm = true
                    } label: {
                        SetRow(
                            icon: "rectangle.portrait.and.arrow.right",
                            iconColor: Theme.danger,
                            title: "Sair",
                            showChevron: false
                        )
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ViewModel

@Observable
final class SettingsHomeViewModel {
    var groupCount: Int?
    var templateCounts: [SetTemplateType: Int] = [:]
    var googleConnected: Bool?
    var errorMessage: String?
    var showError = false

    @MainActor
    func load() async {
        // Contadores são informativos: falhas individuais não bloqueiam a tela.
        if let groups: [SetGroup] = try? await APIClient.shared.get("patient-groups") {
            groupCount = groups.count
        }
        for type in SetTemplateType.allCases {
            if let templates: [SetTemplate] = try? await APIClient.shared.get(
                "templates", query: ["type": type.rawValue]
            ) {
                templateCounts[type] = templates.filter { !$0.isSystem }.count
            }
        }
        if let status: SetGoogleStatus = try? await APIClient.shared.get("integrations/google/status") {
            googleConnected = status.connected
        }
    }
}
