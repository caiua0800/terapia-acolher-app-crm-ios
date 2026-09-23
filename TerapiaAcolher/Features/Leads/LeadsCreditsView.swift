import SwiftUI

/// Créditos de leads — saldo, pacotes, compras recentes e cartões salvos, de
/// verdade. A compra é feita aqui dentro (LeadsCheckoutView), sobre o checkout
/// que fatura no sistema de leads. Até 2026-09-23 esta tela era demonstração.
struct LeadsCreditsView: View {
    @State private var leads = LeadsStore.shared
    @State private var credits: LeadCredits?
    @State private var orders: [LeadsOrder] = []
    @State private var cards: [SavedCard] = []
    @State private var isLoading = true
    @State private var isRetrying = false
    @State private var errorMessage: String?
    @State private var cardToRemove: SavedCard?
    @State private var removingCardId: Int?
    @State private var alerta: String?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content
        }
        .setToolbarTitle("Créditos")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            "Remover este cartão?",
            isPresented: Binding(get: { cardToRemove != nil }, set: { if !$0 { cardToRemove = nil } }),
            titleVisibility: .visible,
            presenting: cardToRemove
        ) { cartao in
            Button("Remover", role: .destructive) { Task { await remove(cartao) } }
            Button("Cancelar", role: .cancel) {}
        } message: { cartao in
            Text("O \(cartao.title) deixa de aparecer nas próximas compras.")
        }
        .alert("Não deu certo", isPresented: Binding(get: { alerta != nil }, set: { if !$0 { alerta = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alerta ?? "")
        }
    }

    // MARK: Estados

    @ViewBuilder
    private var content: some View {
        if isLoading, credits == nil, leads.connection == nil {
            ScrollView {
                VStack(spacing: 14) {
                    SkeletonBlock(height: 150)
                    SkeletonBlock(height: 80)
                    SkeletonBlock(height: 220)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
            }
        } else if leads.connection?.configured == false {
            message(
                icon: "sparkles",
                title: "Créditos indisponíveis",
                text: "A integração com o sistema de leads não está ligada neste ambiente."
            )
        } else if leads.connection != nil, !leads.isConnected {
            VStack(spacing: 18) {
                message(
                    icon: "tray.full",
                    title: "Conecte sua conta de leads",
                    text: "Para ver seu saldo e comprar pacotes, conecte o app à sua conta no portal da Terapia Acolher. É uma vez só."
                )
                NavigationLink {
                    LeadsListView()
                } label: {
                    Text("Conectar meus leads")
                        .font(Theme.body(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(Theme.primary, in: Capsule())
                }
                .buttonStyle(.pressable)
            }
        } else if let credits {
            loaded(credits)
        } else {
            VStack(spacing: 16) {
                message(icon: "exclamationmark.triangle", title: "Não foi possível carregar", text: errorMessage ?? "Tente de novo em instantes.")
                RetryButton(isLoading: isRetrying) {
                    Task {
                        isRetrying = true
                        await load()
                        isRetrying = false
                    }
                }
            }
        }
    }

    private func message(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(Theme.primary)
                .frame(width: 60, height: 60)
                .background(Theme.primarySoft, in: Circle())
            Text(title)
                .font(Theme.serifTitle(21))
                .foregroundStyle(Theme.textPrimary)
            Text(text)
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
    }

    private func loaded(_ c: LeadCredits) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                balanceCard(c)
                monthStrip

                sectionTitle("PACOTES")

                if !c.podeComprar {
                    ThemeCard(padding: 16) {
                        Text(c.motivo ?? "A compra está indisponível agora.")
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if c.pacotes.isEmpty {
                    ThemeCard(padding: 16) {
                        Text("Nenhum pacote disponível agora.")
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(c.pacotes) { pacote in
                            NavigationLink {
                                LeadsCheckoutView(productId: pacote.id)
                            } label: {
                                packageCard(pacote)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }

                footerNote

                if !recentOrders.isEmpty { ordersSection }
                if !cards.isEmpty { cardsSection }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .font(Theme.body(11, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 4)
            .padding(.leading, 2)
    }

    // MARK: Saldo

    private func balanceCard(_ c: LeadCredits) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SEU SALDO")
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: c.isLow ? "arrow.down.right" : "checkmark")
                        .font(.system(size: 9, weight: .bold))
                    Text(c.isLow ? "BAIXO" : "OK")
                        .font(Theme.body(10, weight: .bold))
                        .tracking(0.5)
                }
                .foregroundStyle(c.isLow ? Theme.warning : Theme.success)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(c.isLow ? Theme.warningSoft : Theme.successSoft, in: Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(c.saldo)")
                    .font(Theme.moneyDisplay(46))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text(c.saldo == 1 ? "crédito" : "créditos")
                    .font(Theme.body(16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
            }

            Text(c.isLow
                 ? "Seu saldo está baixo. Escolha um pacote abaixo para continuar recebendo pacientes."
                 : "Cada crédito é um paciente novo chegando para você.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: c.isLow
                    ? [Color(hex: 0xF7EEDC), Color(hex: 0xF3EDE4)]
                    : [Color(hex: 0xE7F0EA), Color(hex: 0xEDE9F4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .animation(.easeInOut(duration: 0.25), value: c.saldo)
    }

    /// Recebidos e convertidos no mês, a partir dos leads reais.
    private var monthCounts: (received: Int, converted: Int) {
        let cal = Calendar.current
        let doMes = leads.leads.filter { cal.isDate($0.receivedAt, equalTo: .now, toGranularity: .month) }
        return (doMes.count, doMes.filter { $0.convertedPatientId != nil }.count)
    }

    private var monthStrip: some View {
        let (recebidos, convertidos) = monthCounts
        return HStack(spacing: 10) {
            miniTile(value: "\(recebidos)", label: "Recebidos", caption: "neste mês", color: Theme.textPrimary)
            miniTile(
                value: "\(convertidos)",
                label: "Viraram paciente",
                caption: recebidos > 0 ? "\(Int((Double(convertidos) / Double(recebidos) * 100).rounded()))% de conversão" : "—",
                color: Theme.success
            )
        }
    }

    private func miniTile(value: String, label: String, caption: String, color: Color) -> some View {
        ThemeCard(padding: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(Theme.moneyDisplay(24))
                    .monospacedDigit()
                    .foregroundStyle(color)
                Text(label)
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(caption)
                    .font(Theme.body(10, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Pacotes

    private func packageCard(_ p: LeadCredits.Pacote) -> some View {
        VStack(spacing: 0) {
            // Faixa reservada mesmo sem selo: sem ela os cards da linha ficam
            // com alturas diferentes e a grade desalinha.
            ZStack {
                if p.selo != nil || p.destaque {
                    Text((p.selo ?? "Mais popular").uppercased())
                        .font(Theme.body(9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.primary, in: Capsule())
                }
            }
            .frame(height: 22)

            Text(p.titulo)
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 6)

            Text("\(p.leads)")
                .font(Theme.moneyDisplay(38))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 2)

            Text(p.leads == 1 ? "lead" : "leads")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)

            Divider().overlay(Theme.border).padding(.vertical, 12)

            if p.emPromocao {
                Text(Formatters.brlCompact(p.precoCheio))
                    .font(Theme.body(11))
                    .strikethrough()
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(Formatters.brlCompact(p.preco))
                .font(Theme.moneyDisplay(19))
                .monospacedDigit()
                .foregroundStyle(Theme.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let porLead = p.precoPorLead {
                Text("\(Formatters.brl(porLead)) por lead")
                    .font(Theme.body(10, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(spacing: 4) {
                Text("Comprar")
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
            }
            .font(Theme.body(12, weight: .semibold))
            .foregroundStyle(Theme.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.primarySoft, in: Capsule())
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(p.destaque ? Theme.primary.opacity(0.55) : Theme.border, lineWidth: p.destaque ? 1.5 : 1)
        )
    }

    private var footerNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Text("Pagamento processado pelo Asaas. Os créditos entram na sua conta assim que o pagamento é confirmado — no Pix e no cartão, na hora.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
        .padding(.horizontal, 2)
    }

    // MARK: Compras recentes

    private var recentOrders: [LeadsOrder] {
        Array(orders.filter { $0.status != "voided" }.prefix(5))
    }

    private var ordersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("COMPRAS RECENTES")
            ThemeCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(recentOrders.enumerated()), id: \.element.id) { i, pedido in
                        if i > 0 { Divider().overlay(Theme.border) }
                        NavigationLink {
                            LeadsOrderView(orderId: pedido.id)
                        } label: {
                            orderRow(pedido)
                        }
                        .buttonStyle(.pressableSubtle)
                    }
                }
            }
        }
    }

    private func orderRow(_ p: LeadsOrder) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text((p.items.first?.title ?? "Pedido \(p.id)") + (p.items.count > 1 ? " + \(p.items.count - 1)" : ""))
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text([CheckoutFormat.date(p.createdAt).map { CheckoutFormat.dayMonthYear.string(from: $0) }, CheckoutFormat.cents(p.totalCents)]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            orderBadge(p)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func orderBadge(_ p: LeadsOrder) -> StatusBadge {
        if p.isPaid { return .init(label: "PAGO", color: Theme.success, background: Theme.successSoft) }
        if p.isPending {
            return .init(label: p.paymentMethod == "pix" ? "PAGAR PIX" : "EM ABERTO", color: Theme.warning, background: Theme.warningSoft)
        }
        return .init(label: p.statusLabel.uppercased(), color: Theme.textSecondary, background: Theme.border.opacity(0.6))
    }

    // MARK: Cartões salvos

    private var cardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("CARTÕES SALVOS")
            ThemeCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { i, cartao in
                        if i > 0 { Divider().overlay(Theme.border) }
                        HStack(spacing: 12) {
                            CardBrandBadge(brand: cartao.brand)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cartao.title)
                                    .font(Theme.body(14, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(cartao.isActive ? (cartao.holderName ?? "Pronto para usar") : "Confirmando com a operadora")
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            AsyncIconButton(
                                icon: "trash",
                                isLoading: removingCardId == cartao.id,
                                isEnabled: removingCardId == nil,
                                tint: Theme.danger
                            ) {
                                cardToRemove = cartao
                            }
                            .accessibilityLabel("Remover \(cartao.title)")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                }
            }
            Text("Guardamos só um código seguro do Asaas, nunca o número do cartão.")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 2)
        }
    }

    // MARK: Ações

    @MainActor
    private func load() async {
        errorMessage = nil
        if leads.connection == nil || leads.leads.isEmpty { await leads.load() }
        guard leads.isConnected else {
            isLoading = false
            return
        }
        do {
            async let c = LeadsCheckoutAPI.credits()
            async let o = LeadsCheckoutAPI.orders()
            async let k = LeadsCheckoutAPI.savedCards()
            credits = try await c
            // Compras e cartões são complemento: falhar neles não derruba a tela.
            orders = (try? await o) ?? orders
            cards = (try? await k)?.cards ?? cards
        } catch is CancellationError {
        } catch let e as APIError {
            errorMessage = e.message
        } catch {
            errorMessage = "Não foi possível carregar seus créditos."
        }
        isLoading = false
    }

    @MainActor
    private func remove(_ cartao: SavedCard) async {
        removingCardId = cartao.id
        defer { removingCardId = nil }
        do {
            try await LeadsCheckoutAPI.removeCard(cartao.id)
            Haptics.success()
            withAnimation { cards.removeAll { $0.id == cartao.id } }
        } catch let e as APIError {
            alerta = e.message
        } catch {
            alerta = "Não foi possível remover o cartão."
        }
    }
}

/// Bandeira como selo pequeno: cor e nome, sem logo de terceiros.
struct CardBrandBadge: View {
    let brand: String?

    var body: some View {
        let nome = CardBrand.displayName(brand)
        let (fundo, texto): (Color, Color) = switch nome {
        case "Visa": (Color(hex: 0x1A1F71), .white)
        case "Mastercard": (Color(hex: 0xEB001B), .white)
        case "Elo": (Color(hex: 0x111111), Color(hex: 0xFFCB05))
        case "Amex": (Color(hex: 0x2E77BB), .white)
        case "Hipercard": (Color(hex: 0xB3131B), .white)
        case "Diners": (Color(hex: 0x0079BE), .white)
        default: (Theme.background, Theme.textSecondary)
        }
        Text(nome == "Mastercard" ? "MC" : nome == "Cartão" ? "•••" : String(nome.uppercased().prefix(4)))
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(texto)
            .frame(width: 36, height: 24)
            .background(fundo, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(nome == "Cartão" ? Theme.border : .clear, lineWidth: 1))
            .accessibilityHidden(true)
    }
}
