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
        ScrollViewReader { rolagem in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    saldo(c) {
                        withAnimation(.easeInOut(duration: 0.35)) { rolagem.scrollTo("pacotes", anchor: .top) }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Escolha seu pacote")
                                .font(Theme.serifTitle(22))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Quanto maior o pacote, menor o preço de cada paciente novo.")
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .id("pacotes")

                        if c.podeComprar { formas(c) }

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
                            let maiorPorLead = c.pacotes.compactMap(\.precoPorLead).max() ?? 0
                            VStack(spacing: 16) {
                                ForEach(c.pacotes) { pacote in
                                    NavigationLink {
                                        LeadsCheckoutView(productId: pacote.id)
                                    } label: {
                                        packageCard(pacote, maiorPorLead: maiorPorLead)
                                    }
                                    .buttonStyle(.pressableSubtle)
                                }
                            }
                            .padding(.top, 6)
                        }

                        garantias
                    }

                    if !orders.isEmpty { MinhasCompras(orders: orders) }
                    if !cards.isEmpty { cardsSection }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
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

    /// "Dura cerca de…" pelo ritmo dos últimos 30 dias. Sem ritmo, não chuta.
    private func duracao(_ saldo: Int) -> String? {
        guard saldo > 0 else { return nil }
        let limite = Date().addingTimeInterval(-30 * 86_400)
        let ultimos = leads.leads.filter { $0.receivedAt >= limite }.count
        guard ultimos > 0 else { return nil }
        let dias = Int((Double(saldo) / (Double(ultimos) / 30)).rounded())
        let quando = dias < 2 ? "cerca de 1 dia"
            : dias < 14 ? "cerca de \(dias) dias"
            : dias < 60 ? "cerca de \(Int((Double(dias) / 7).rounded())) semanas"
            : "mais de 2 meses"
        return "No seu ritmo (\(ultimos) \(ultimos == 1 ? "lead" : "leads") nos últimos 30 dias), dura \(quando)."
    }

    private func saldo(_ c: LeadCredits, recarregar: @escaping () -> Void) -> some View {
        let zerado = c.saldo <= 0
        let baixo = c.isLow
        let (recebidos, convertidos) = monthCounts
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("SEU SALDO DE LEADS")
                    .font(Theme.body(10.5, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(.white.opacity(0.55))
                Text(zerado ? "ZERADO" : baixo ? "BAIXO" : "EM DIA")
                    .font(Theme.body(10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(zerado || baixo ? .white : Color(hex: 0x8FD9B6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(zerado ? Theme.danger : baixo ? Theme.warning : .white.opacity(0.12), in: Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(c.saldo)")
                    .font(Theme.moneyDisplay(60))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(c.saldo == 1 ? "crédito" : "créditos")
                    .font(Theme.body(17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(zerado
                     ? "Seu saldo acabou — novos pacientes param de chegar até você recarregar."
                     : baixo
                        ? "Seu saldo está acabando. Recarregue para não ficar sem receber pacientes."
                        : "Cada crédito é uma pessoa procurando terapia chegando até você.")
                    .font(Theme.body(14))
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                if let d = duracao(c.saldo) {
                    Label(d, systemImage: "clock")
                        .font(Theme.body(12))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if c.podeComprar, !c.pacotes.isEmpty {
                Button {
                    Haptics.tap()
                    recarregar()
                } label: {
                    Label("Recarregar créditos", systemImage: "arrow.down")
                        .font(Theme.body(14.5, weight: .semibold))
                        .foregroundStyle(baixo ? Theme.ink : .white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                        .background(baixo ? Color.white : Color.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.pressable)
            }

            HStack(spacing: 8) {
                numeroDoHero("\(recebidos)", "Recebidos no mês")
                numeroDoHero("\(convertidos)", "Viraram paciente")
                numeroDoHero(recebidos > 0 ? "\(Int((Double(convertidos) / Double(recebidos) * 100).rounded()))%" : "—", "Conversão")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack(alignment: .topTrailing) {
                Theme.ink
                Circle()
                    .fill(zerado ? Theme.danger : baixo ? Theme.warning : Theme.primary)
                    .frame(width: 240, height: 240)
                    .blur(radius: 70)
                    .opacity(0.45)
                    .offset(x: 90, y: -110)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .animation(.easeInOut(duration: 0.25), value: c.saldo)
    }

    private func numeroDoHero(_ valor: String, _ rotulo: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(valor)
                .font(Theme.moneyDisplay(20))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(rotulo)
                .font(Theme.body(10.5))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    /// Recebidos e convertidos no mês, a partir dos leads reais.
    private var monthCounts: (received: Int, converted: Int) {
        let cal = Calendar.current
        let doMes = leads.leads.filter { cal.isDate($0.receivedAt, equalTo: .now, toGranularity: .month) }
        return (doMes.count, doMes.filter { $0.convertedPatientId != nil }.count)
    }

    private func formas(_ c: LeadCredits) -> some View {
        let itens: [(String, String)] = [
            c.formasDePagamento.pix == true ? ("Pix", "qrcode") : nil,
            c.formasDePagamento.cartao == true ? (c.maxParcelas > 1 ? "Cartão em até \(c.maxParcelas)x" : "Cartão", "creditcard") : nil,
            c.formasDePagamento.boleto == true ? ("Boleto", "doc.text") : nil,
        ].compactMap { $0 }
        return FlowLayout(spacing: 6) {
            ForEach(itens, id: \.0) { item in
                Label(item.0, systemImage: item.1)
                    .font(Theme.body(12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
            }
        }
    }

    // MARK: Pacotes

    private func packageCard(_ p: LeadCredits.Pacote, maiorPorLead: Double) -> some View {
        let economia: Int = {
            guard let porLead = p.precoPorLead, maiorPorLead > 0 else { return 0 }
            return Int(((1 - porLead / maiorPorLead) * 100).rounded())
        }()
        let etiqueta = p.selo ?? (p.destaque ? "Mais popular" : nil)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(p.titulo)
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                if economia >= 5 {
                    Text("−\(economia)% por lead")
                        .font(Theme.body(11, weight: .bold))
                        .foregroundStyle(Theme.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.successSoft, in: Capsule())
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(p.leads)")
                    .font(Theme.moneyDisplay(44))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(p.leads == 1 ? "lead" : "leads")
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 8)
            if p.reposicoes > 0 {
                Text("+ \(p.reposicoes) \(p.reposicoes == 1 ? "reposição" : "reposições")")
                    .font(Theme.body(12.5, weight: .medium))
                    .foregroundStyle(Theme.primary)
            }

            Divider().overlay(Theme.border).padding(.vertical, 14)

            if p.emPromocao {
                Text(Formatters.brlCompact(p.precoCheio))
                    .font(Theme.body(12))
                    .strikethrough()
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(Formatters.brlCompact(p.preco))
                    .font(Theme.moneyDisplay(26))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let porLead = p.precoPorLead {
                    Text("\(Formatters.brl(porLead))/lead")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if p.emPromocao, let ate = CheckoutFormat.date(p.promocaoAte) {
                Text("Promoção até \(CheckoutFormat.dayMonthYear.string(from: ate))")
                    .font(Theme.body(11.5, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                    .padding(.top, 4)
            }

            if let descricao = p.descricao, !descricao.isEmpty {
                Text(descricao)
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 10)
            }
            if !p.beneficios.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(p.beneficios, id: \.self) { b in
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.success)
                                .padding(.top, 3)
                            Text(b)
                                .font(Theme.body(12.5))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .padding(.top, 10)
            }

            HStack(spacing: 5) {
                Text("Comprar")
                Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold))
            }
            .font(Theme.body(14.5, weight: .semibold))
            .foregroundStyle(p.destaque ? .white : Theme.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(p.destaque ? Theme.primary : Theme.primarySoft, in: Capsule())
            .padding(.top, 16)
        }
        .padding(18)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(p.destaque ? Theme.primary : Theme.border, lineWidth: p.destaque ? 1.5 : 1)
        )
        .shadow(color: p.destaque ? Theme.primary.opacity(0.16) : .clear, radius: 14, y: 8)
        .overlay(alignment: .topLeading) {
            if let etiqueta {
                Text(etiqueta.uppercased())
                    .font(Theme.body(10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.primary, in: Capsule())
                    .offset(x: 18, y: -11)
            }
        }
    }

    private var garantias: some View {
        VStack(spacing: 8) {
            garantia("lock.shield", "Pagamento seguro", "Processado pelo Asaas. Nenhum dado de cartão fica no CRM.")
            garantia("clock", "Crédito na hora", "No Pix e no cartão, os créditos entram assim que o pagamento é confirmado.")
            garantia("tray.full", "Direto no seu CRM", "Os leads aparecem em Meus leads, prontos para chamar no WhatsApp.")
        }
        .padding(.top, 6)
    }

    private func garantia(_ icone: String, _ titulo: String, _ texto: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icone)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .frame(width: 32, height: 32)
                .background(Theme.primarySoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                    .font(Theme.body(13.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(texto)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
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

// MARK: - Minhas compras

/// Pedidos com busca (pacote ou nº), período, status e 20 por vez. O sistema
/// de leads devolve os 50 mais recentes; filtro e paginação acontecem aqui.
private struct MinhasCompras: View {
    let orders: [LeadsOrder]

    @State private var busca = ""
    @State private var usarDe = false
    @State private var de = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var usarAte = false
    @State private var ate = Date()
    @State private var status = "todos"
    @State private var limite = 20

    private var todos: [LeadsOrder] { orders.filter { $0.status != "voided" } }

    private var filtrados: [LeadsOrder] {
        let termo = busca.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "pt_BR"))
            .trimmingCharacters(in: .whitespaces)
        let cal = Calendar.current
        return todos.filter { p in
            if status != "todos", p.status != status { return false }
            if let data = CheckoutFormat.date(p.createdAt) {
                if usarDe, data < cal.startOfDay(for: de) { return false }
                if usarAte, let fim = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: ate)), data >= fim { return false }
            }
            guard !termo.isEmpty else { return true }
            let texto = "\(p.items.map(\.title).joined(separator: " ")) \(p.id) \(p.couponCode ?? "")"
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "pt_BR"))
            return texto.contains(termo)
        }
    }

    private var temFiltro: Bool { !busca.isEmpty || usarDe || usarAte || status != "todos" }

    var body: some View {
        let lista = filtrados
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Minhas compras")
                    .font(Theme.serifTitle(21))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(todos.count) \(todos.count == 1 ? "pedido" : "pedidos") · os 50 mais recentes")
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.textSecondary)
            }

            ThemeCard(padding: 0) {
                VStack(spacing: 0) {
                    filtros
                    Divider().overlay(Theme.border)
                    if lista.isEmpty {
                        Text("Nenhum pedido com esses filtros.")
                            .font(Theme.body(13.5))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else {
                        ForEach(Array(lista.prefix(limite).enumerated()), id: \.element.id) { i, pedido in
                            if i > 0 { Divider().overlay(Theme.border) }
                            NavigationLink {
                                LeadsOrderView(orderId: pedido.id)
                            } label: {
                                linha(pedido)
                            }
                            .buttonStyle(.pressableSubtle)
                        }
                        Divider().overlay(Theme.border)
                        HStack {
                            Text("Mostrando \(min(limite, lista.count)) de \(lista.count)")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            if lista.count > limite {
                                Button {
                                    Haptics.tap()
                                    withAnimation { limite += 20 }
                                } label: {
                                    Text("Carregar mais")
                                        .font(Theme.body(13, weight: .semibold))
                                        .foregroundStyle(Theme.primary)
                                }
                                .buttonStyle(.pressable)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .onChange(of: busca) { _, _ in limite = 20 }
        .onChange(of: status) { _, _ in limite = 20 }
    }

    private var filtros: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField("Buscar pelo pacote ou nº do pedido", text: $busca)
                    .font(Theme.body(14.5))
                    .autocorrectionDisabled()
                if !busca.isEmpty {
                    Button { busca = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 8) {
                Menu {
                    Picker("Status", selection: $status) {
                        Text("Todos").tag("todos")
                        ForEach(Array(Set(todos.map(\.status))).sorted(), id: \.self) { s in
                            Text(rotuloStatus(s)).tag(s)
                        }
                    }
                } label: {
                    pilula(status == "todos" ? "Status: todos" : rotuloStatus(status), ativo: status != "todos")
                }
                Menu {
                    Toggle("A partir de uma data", isOn: $usarDe)
                    Toggle("Até uma data", isOn: $usarAte)
                } label: {
                    pilula(usarDe || usarAte ? "Período definido" : "Qualquer data", ativo: usarDe || usarAte)
                }
                Spacer(minLength: 0)
                if temFiltro {
                    Button("Limpar") {
                        busca = ""
                        usarDe = false
                        usarAte = false
                        status = "todos"
                    }
                    .font(Theme.body(12.5, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                }
            }
            if usarDe {
                DatePicker("De", selection: $de, in: ...(usarAte ? ate : .now), displayedComponents: .date)
                    .font(Theme.body(13.5))
                    .environment(\.locale, Locale(identifier: "pt_BR"))
            }
            if usarAte {
                DatePicker("Até", selection: $ate, in: (usarDe ? de : .distantPast)..., displayedComponents: .date)
                    .font(Theme.body(13.5))
                    .environment(\.locale, Locale(identifier: "pt_BR"))
            }
        }
        .padding(12)
        .tint(Theme.primary)
    }

    private func pilula(_ texto: String, ativo: Bool) -> some View {
        HStack(spacing: 4) {
            Text(texto).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
        }
        .font(Theme.body(12.5, weight: ativo ? .semibold : .regular))
        .foregroundStyle(ativo ? Theme.primary : Theme.textPrimary)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(ativo ? Theme.primarySoft : Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(ativo ? .clear : Theme.border, lineWidth: 1))
    }

    private func rotuloStatus(_ s: String) -> String {
        switch s {
        case "pending": "Aguardando pagamento"
        case "paid": "Pago"
        case "failed": "Não aprovado"
        case "canceled": "Cancelado"
        case "expired": "Vencido"
        case "refunded": "Estornado"
        default: s
        }
    }

    private func linha(_ p: LeadsOrder) -> some View {
        let data = CheckoutFormat.date(p.createdAt)
        let metodo: String = switch p.paymentMethod {
        case "pix": "Pix"
        case "credit_card": "Cartão" + (p.cardLast4.map { " final \($0)" } ?? "") + (p.installments > 1 ? " · \(p.installments)x" : "")
        case "boleto": "Boleto"
        default: p.paymentMethod
        }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text((p.items.first?.title ?? "Pedido \(p.id)") + (p.items.count > 1 ? " + \(p.items.count - 1)" : ""))
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(["Nº \(p.id)", data.map { CheckoutFormat.dayTime.string(from: $0) }, metodo].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.body(11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Text("\(p.leadsQty) \(p.leadsQty == 1 ? "lead" : "leads")" + ((p.replenishmentsQty ?? 0) > 0 ? " + \(p.replenishmentsQty!) rep." : ""))
                    .font(Theme.body(11.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Text(CheckoutFormat.cents(p.totalCents))
                    .font(Theme.body(14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                badge(p)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func badge(_ p: LeadsOrder) -> StatusBadge {
        if p.isPaid { return .init(label: "PAGO", color: Theme.success, background: Theme.successSoft) }
        if p.isPending {
            return .init(label: p.paymentMethod == "pix" ? "PAGAR PIX" : "EM ABERTO", color: Theme.warning, background: Theme.warningSoft)
        }
        return .init(label: p.statusLabel.uppercased(), color: Theme.textSecondary, background: Theme.border.opacity(0.6))
    }
}
