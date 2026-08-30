import SwiftUI

/// Lista de leads recebidos. **Dados simulados** — ver LeadsModels.swift.
struct LeadsListView: View {
    @State private var store = LeadsStore.shared
    @State private var filter: Filter = .abertos

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

            VStack(spacing: 0) {
                header
                chips

                if filtered.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "tray",
                        title: "Nada por aqui",
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
                }
            }
        }
        .setToolbarTitle("Meus leads")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyMessage: String {
        switch filter {
        case .atrasados: "Nenhum lead esperando há mais de um dia. Bom trabalho."
        case .novos: "Você já falou com todo mundo que chegou."
        default: "Nenhum lead neste filtro."
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

                Text(lead.reason)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
