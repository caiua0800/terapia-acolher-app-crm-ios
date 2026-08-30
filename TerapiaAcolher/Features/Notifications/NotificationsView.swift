import Observation
import SwiftUI

// MARK: - Modelo (prefixo Notif* — reservado a este módulo)

/// GET notifications — item da central de notificações.
struct NotifItem: Decodable, Identifiable {
    let id: String
    let type: String
    let title: String
    let body: String?
    let data: NotifData?
    var readAt: Date?
    let createdAt: Date

    enum CodingKeys: CodingKey { case id, type, title, body, data, readAt, createdAt }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        // `data` é JSON livre — decodifica de forma tolerante.
        data = try? container.decodeIfPresent(NotifData.self, forKey: .data)
        readAt = try container.decodeIfPresent(Date.self, forKey: .readAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    var isUnread: Bool { readAt == nil }

    /// Ícone e cor por tipo, fiéis ao MVP: calendário verde (sessão),
    /// cifrão âmbar (cobrança), check verde (atendida), alerta vermelho
    /// (falta), asterisco lilás (modelo atualizado).
    var icon: String {
        switch type {
        case "SESSION_SOON": "calendar"
        case "CHARGE_DUE": "dollarsign"
        case "SESSION_ATTENDED": "checkmark"
        case "SESSION_MISSED": "exclamationmark.circle"
        case "TEMPLATE_UPDATED": "asterisk"
        default: "bell"
        }
    }

    var tint: Color {
        switch type {
        case "SESSION_SOON": Theme.primary
        case "CHARGE_DUE": Theme.warning
        case "SESSION_ATTENDED": Theme.success
        case "SESSION_MISSED": Theme.danger
        case "TEMPLATE_UPDATED": Color(hex: 0xB9A6D9)
        default: Color(hex: 0x7FA8C9)
        }
    }
}

/// Payload contextual da notificação (chaves conhecidas, todas opcionais).
struct NotifData: Decodable {
    let sessionId: String?
    let chargeId: String?
    let templateId: String?
}

/// Filtros locais (chips) — Sessões = SESSION_*; Financeiro = CHARGE_*.
enum NotifFilter: String, CaseIterable, Identifiable {
    case tudo = "Tudo"
    case naoLidas = "Não lidas"
    case sessoes = "Sessões"
    case financeiro = "Financeiro"

    var id: String { rawValue }

    func matches(_ item: NotifItem) -> Bool {
        switch self {
        case .tudo: true
        case .naoLidas: item.isUnread
        case .sessoes: item.type.hasPrefix("SESSION")
        case .financeiro: item.type.hasPrefix("CHARGE")
        }
    }
}

// MARK: - Tela

/// Central de notificações — fiel ao MVP: MARCAR TODAS no topo,
/// chips de filtro, células com ícone por tipo, hora relativa e dot de não lida.
struct NotificationsView: View {
    @State private var viewModel = NotificationsViewModel.shared

    @State private var push = PushManager.shared
    @State private var isAskingPush = false

    /// Convite pra ligar as notificações. Pedir permissão aqui, e não na
    /// primeira abertura do app, é deliberado: o iOS só mostra o alerta do
    /// sistema UMA vez na vida do app — gastar isso antes de o terapeuta
    /// entender o valor é trocar um "sim" provável por um "não" definitivo.
    @ViewBuilder
    private var pushPermissionCard: some View {
        if let status = push.authorization, status != .authorized {
            let negado = status == .denied
            ThemeCard(padding: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 40, height: 40)
                        .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 11))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(negado ? "Notificações desativadas" : "Ative as notificações")
                            .font(Theme.body(14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Avisamos de sessões e pagamentos confirmados.")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 6)

                    Button {
                        Haptics.tap()
                        if negado {
                            push.openSystemSettings()
                        } else {
                            isAskingPush = true
                            Task {
                                await push.requestAuthorization()
                                isAskingPush = false
                            }
                        }
                    } label: {
                        Group {
                            if isAskingPush {
                                ProgressView().controlSize(.small).tint(Theme.primary)
                            } else {
                                Text(negado ? "Ajustes" : "Ativar")
                                    .font(Theme.body(13, weight: .semibold))
                            }
                        }
                        .foregroundStyle(Theme.primary)
                        .frame(minWidth: 62)
                        .padding(.vertical, 8)
                        .background(Theme.primarySoft, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                    .disabled(isAskingPush)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 10)
        }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                pushPermissionCard
                chips
                if viewModel.isLoading {
                    Spacer()
                    ProgressView().tint(Theme.primary)
                    Spacer()
                } else if viewModel.filtered.isEmpty {
                    ScrollView {
                        emptyState
                            .padding(.top, 60)
                    }
                    .refreshable { await viewModel.load() }
                } else {
                    list
                }
            }
        }
        .setToolbarTitle("Notificações")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Texto em duas linhas era truncado pela barra ("MARCAR…").
                // Ícone único: cabe sempre e vira spinner enquanto marca.
                AsyncIconButton(
                    icon: "checkmark.circle",
                    isLoading: viewModel.isMarkingAll,
                    isEnabled: viewModel.hasUnread,
                    tint: Theme.textPrimary,
                    size: 17
                ) {
                    Task { await viewModel.markAllRead() }
                }
                .accessibilityLabel("Marcar todas como lidas")
            }
        }
        .task { await viewModel.load() }
        .alert("Ops", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Algo deu errado.")
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NotifFilter.allCases) { filter in
                    FilterChip(label: filter.rawValue, isSelected: viewModel.filter == filter) {
                        viewModel.filter = filter
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 12)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.filtered) { item in
                    Button {
                        Task { await viewModel.markRead(item) }
                    } label: {
                        NotifCell(item: item)
                    }
                    .buttonStyle(.pressableSubtle)
                    InsetDivider(
                        leading: Theme.screenPadding + 50,
                        trailing: Theme.screenPadding
                    )
                }
            }
        }
        .refreshable { await viewModel.load() }
    }

    private var emptyState: some View {
        switch viewModel.filter {
        case .tudo:
            EmptyStateView(
                icon: "bell",
                title: "Tudo tranquilo por aqui",
                message: "Quando algo importante acontecer — sessões chegando, cobranças, faltas — a gente te avisa aqui."
            )
        case .naoLidas:
            EmptyStateView(
                icon: "checkmark.circle",
                title: "Nenhuma pendente",
                message: "Você já leu todas as suas notificações. Respira fundo e segue o dia."
            )
        case .sessoes:
            EmptyStateView(
                icon: "calendar",
                title: "Nada sobre sessões",
                message: "Avisos de sessões chegando, atendidas ou faltas vão aparecer aqui."
            )
        case .financeiro:
            EmptyStateView(
                icon: "dollarsign.circle",
                title: "Nada sobre cobranças",
                message: "Lembretes de cobrança e vencimentos vão aparecer aqui."
            )
        }
    }
}

// MARK: - Célula

private struct NotifCell: View {
    let item: NotifItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(item.tint)
                .frame(width: 38, height: 38)
                .background(item.tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                if let body = item.body, !body.isEmpty {
                    Text(body)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                Text(NotifRelativeTime.format(item.createdAt))
                    .font(Theme.body(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                if item.isUnread {
                    Circle()
                        .fill(Theme.primary)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 14)
        .background(item.isUnread ? Theme.primarySoft.opacity(0.35) : Color.clear)
        .contentShape(Rectangle())
    }
}

/// Hora relativa em PT-BR, como no MVP: "13:00" (hoje), "ontem", "08/07".
enum NotifRelativeTime {
    private static let hora: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter
    }()

    private static let diaMes: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter
    }()

    static func format(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return hora.string(from: date) }
        if calendar.isDateInYesterday(date) { return "ontem" }
        return diaMes.string(from: date)
    }
}

// MARK: - ViewModel

@Observable
final class NotificationsViewModel {
    /// Instância única: o estado sobrevive à navegação.
    ///
    /// Antes cada tela criava o seu view model como `@State` local, então ele
    /// MORRIA ao sair — voltar para cá dois segundos depois dava spinner e
    /// requisição de novo. Era o que mais fazia o app parecer lento, mesmo com
    /// a API respondendo rápido. Agora a tela volta com o conteúdo já pintado e
    /// só atualiza por baixo.
    static let shared = NotificationsViewModel()

    var items: [NotifItem] = []
    var filter: NotifFilter = .tudo
    var isLoading = true
    var isMarkingAll = false
    var errorMessage: String?
    var showError = false

    var filtered: [NotifItem] { items.filter { filter.matches($0) } }
    var hasUnread: Bool { items.contains(where: \.isUnread) }

    @MainActor
    func load() async {
        do {
            items = try await APIClient.shared.get("notifications")
            isLoading = false
        } catch {
            isLoading = false
            present(error)
        }
    }

    /// Toca numa notificação → marca como lida (MVP: navegação contextual
    /// via data.sessionId fica pra fase da agenda).
    @MainActor
    func markRead(_ item: NotifItem) async {
        guard item.isUnread else { return }
        // Otimista: marca local primeiro, reverte se a API falhar.
        let previous = items
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].readAt = Date()
        }
        do {
            let _: EmptyResponse = try await APIClient.shared.patch("notifications/\(item.id)/read")
        } catch {
            items = previous
            present(error)
        }
    }

    @MainActor
    func markAllRead() async {
        let previous = items
        let now = Date()
        isMarkingAll = true
        defer { isMarkingAll = false }
        items = items.map { item in
            var copy = item
            if copy.isUnread { copy.readAt = now }
            return copy
        }
        do {
            let _: EmptyResponse = try await APIClient.shared.patch("notifications/read-all")
        } catch {
            items = previous
            present(error)
        }
    }

    @MainActor
    private func present(_ error: Error) {
        errorMessage = (error as? APIError)?.message ?? "Não foi possível carregar. Verifique sua conexão."
        showError = true
    }
}
