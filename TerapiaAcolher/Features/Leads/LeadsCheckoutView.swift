import SwiftUI

/// Checkout de créditos dentro do app: produto, order bumps, dados, Pix /
/// cartão / boleto, cartão salvo e resumo com o botão de pagar. Criado o
/// pedido, a mesma tela vira o acompanhamento (LeadsOrderView) — voltar leva
/// a Créditos, nunca de novo ao formulário de uma compra já feita.
struct LeadsCheckoutView: View {
    @State private var model: LeadsCheckoutModel
    @State private var isRetrying = false
    @State private var toastText: String?

    init(productId: Int) {
        _model = State(initialValue: LeadsCheckoutModel(productId: productId))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()
            if let pedido = model.createdOrder {
                LeadsOrderView(orderId: pedido.id, initial: pedido, showsTitle: false)
            } else {
                content
            }
            if let toastText {
                Text(toastText)
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Theme.ink, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .setToolbarTitle(model.createdOrder == nil ? "Comprar créditos" : "Pedido")
        .navigationBarTitleDisplayMode(.inline)
        .task { if model.product == nil { await model.load() } }
        .onChange(of: model.toast) { _, novo in
            guard let novo else { return }
            withAnimation { toastText = novo }
            model.toast = nil
            Task {
                try? await Task.sleep(for: .seconds(3.2))
                withAnimation { toastText = nil }
            }
        }
        .sheet(isPresented: Binding(
            get: { model.askingPassword },
            set: { if !$0 { model.cancelPassword() } }
        )) {
            PasswordConfirmSheet(model: model)
                .presentationDetents([.height(330)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Estados

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ScrollView {
                VStack(spacing: 14) {
                    SkeletonBlock(height: 130, cornerRadius: Theme.cornerRadius)
                    SkeletonBlock(height: 200, cornerRadius: Theme.cornerRadius)
                    SkeletonBlock(height: 160, cornerRadius: Theme.cornerRadius)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
            }
        } else if let e = model.loadError {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.danger)
                    .frame(width: 56, height: 56)
                    .background(Theme.dangerSoft, in: Circle())
                Text(e.message)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                if e.code == "leads_desconectado" {
                    NavigationLink("Conectar meus leads") { LeadsListView() }
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                } else {
                    RetryButton(isLoading: isRetrying) {
                        Task {
                            isRetrying = true
                            await model.load()
                            isRetrying = false
                        }
                    }
                }
            }
        } else if let p = model.product {
            form(p)
        }
    }

    private func form(_ p: CheckoutProduct) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    productCard(p.product)
                    ForEach(p.offers, id: \.offerId) { oferta in
                        OrderBumpCard(
                            offer: oferta,
                            isOn: model.selectedOffers.contains(oferta.offerId ?? -1)
                        ) {
                            if let id = oferta.offerId { model.toggleOffer(id) }
                        }
                    }
                    if p.pagamento.precisaCpf || p.pagamento.precisaEmail { dataCard(p) }
                    paymentCard(p)
                    summaryCard
                    if let g = p.product.guaranteeText, !g.isEmpty { guarantee(g) }
                    if let faq = p.product.faq, !faq.isEmpty { FAQCard(items: faq) }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            payBar
        }
    }

    // MARK: Produto

    private func productCard(_ item: CheckoutItem) -> some View {
        ThemeCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    Text(item.leadsQty > 0 ? "\(item.leadsQty)" : "★")
                        .font(Theme.moneyDisplay(26))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 64, height: 64)
                        .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VOCÊ ESTÁ COMPRANDO")
                            .font(Theme.body(10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.textSecondary)
                        Text(item.title)
                            .font(Theme.serifTitle(20))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if item.leadsQty > 0 {
                            Text("\(item.leadsQty) contatos qualificados e triados" + (item.replenishmentsQty > 0 ? " · \(item.replenishmentsQty) reposições" : ""))
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if item.onSale {
                                Text(CheckoutFormat.cents(item.priceCents))
                                    .font(Theme.body(12))
                                    .strikethrough()
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Text(CheckoutFormat.cents(item.unitPriceCents))
                                .font(Theme.moneyDisplay(19))
                                .foregroundStyle(Theme.primary)
                            if item.onSale, let selo = item.promoLabel {
                                StatusBadge(label: selo, color: Theme.success, background: Theme.successSoft)
                            }
                        }
                    }
                }
                if let d = item.description, !d.isEmpty {
                    Text(d)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let bullets = item.bullets, !bullets.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(bullets, id: \.self) { b in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.success)
                                    .padding(.top, 3)
                                Text(b)
                                    .font(Theme.body(13))
                                    .foregroundStyle(Theme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Dados

    private func dataCard(_ p: CheckoutProduct) -> some View {
        ThemeCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Seus dados")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Pedimos uma vez só: ficam salvos para as próximas compras.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                if p.pagamento.precisaCpf {
                    GwField(label: "CPF", erro: model.fieldErrors["cpf"]) {
                        TextField("000.000.000-00", text: Binding(
                            get: { model.cpf },
                            set: { model.cpf = CheckoutFormat.maskCpf($0) }
                        ))
                        .keyboardType(.numberPad)
                    }
                }
                if p.pagamento.precisaEmail {
                    GwField(label: "E-mail para o comprovante", erro: model.fieldErrors["email"]) {
                        TextField("voce@exemplo.com", text: $model.email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
            }
        }
    }

    // MARK: Pagamento

    private func paymentCard(_ p: CheckoutProduct) -> some View {
        ThemeCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Forma de pagamento")
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                HStack(alignment: .top, spacing: 8) {
                    ForEach(model.methods) { m in
                        methodButton(m, maxParcelas: p.pagamento.maxParcelas)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                switch model.method {
                case .pix:
                    note(
                        "O QR code aparece na próxima tela. " + (model.leadsInOrder > 0 ? "Pagou, os contatos entram no seu saldo na hora." : "Pagou, a compra é confirmada na hora."),
                        color: Theme.success,
                        background: Theme.successSoft
                    )
                case .boleto:
                    note(
                        "O boleto vence em 3 dias. " + (model.leadsInOrder > 0 ? "Os contatos entram" : "A compra é confirmada") + " quando o banco compensar, em até 1 dia útil.",
                        color: Theme.textSecondary,
                        background: Theme.background
                    )
                case .creditCard:
                    cardSection(p)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.easeInOut(duration: 0.2), value: model.method)
        .animation(.easeInOut(duration: 0.2), value: model.savedChoice)
    }

    private func methodButton(_ m: CheckoutMethod, maxParcelas: Int) -> some View {
        let ativo = model.method == m
        let dica = switch m {
        case .pix: "Aprovação na hora"
        case .creditCard: maxParcelas > 1 ? "Até \(maxParcelas)x" : "À vista"
        case .boleto: "Até 1 dia útil"
        }
        return Button {
            Haptics.tap()
            model.method = m
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: m.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ativo ? Theme.primary : Theme.textSecondary)
                Text(m.title)
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(ativo ? Theme.textPrimary : Theme.textPrimary.opacity(0.8))
                Text(dica)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(ativo ? Theme.primarySoft.opacity(0.6) : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ativo ? Theme.primary : Theme.border, lineWidth: ativo ? 1.5 : 1))
        }
        .buttonStyle(.pressableSubtle)
        .accessibilityAddTraits(ativo ? .isSelected : [])
        .accessibilityLabel(m.title)
    }

    private func note(_ text: String, color: Color, background: Color) -> some View {
        Text(text)
            .font(Theme.body(13))
            .foregroundStyle(color)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 12))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func cardSection(_ p: CheckoutProduct) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.installmentTable.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PARCELAS")
                        .font(Theme.body(10, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(Theme.textSecondary)
                    Menu {
                        ForEach(model.installmentTable, id: \.installments) { parcela in
                            Button(installmentLabel(parcela)) {
                                Haptics.tap()
                                model.installments = parcela.installments
                            }
                        }
                    } label: {
                        HStack {
                            Text(model.chosenInstallment.map(installmentLabel) ?? "")
                                .font(Theme.body(15))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                    }
                    .accessibilityLabel("Parcelas")
                    if let c = model.chosenInstallment, c.installments > 1 {
                        Text("Acréscimo de \(pct(c.surchargePct))% do parcelamento já incluído no total.")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            if !model.activeCards.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PAGAR COM")
                        .font(Theme.body(10, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(model.activeCards) { cartao in
                        cardOption(isOn: model.savedChoice == cartao.id, label: cartao.title) {
                            model.savedChoice = cartao.id
                        } content: {
                            CardBrandBadge(brand: cartao.brand)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(cartao.title)
                                    .font(Theme.body(14, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                if let h = cartao.holderName {
                                    Text(h)
                                        .font(Theme.body(11))
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    cardOption(isOn: model.savedChoice == nil, label: "Usar outro cartão") {
                        model.savedChoice = nil
                    } content: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 36, height: 24)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.border, lineWidth: 1))
                        Text("Usar outro cartão")
                            .font(Theme.body(14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }

            if model.cardInUse == nil {
                newCardForm(p)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield").font(.system(size: 12))
                    Text("Para pagar, você confirma a senha do app. Nenhum dado do cartão é digitado de novo.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func cardOption<C: View>(
        isOn: Bool,
        label: String,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> C
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isOn ? Theme.primary : Theme.border)
                content()
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(isOn ? Theme.primarySoft.opacity(0.5) : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isOn ? Theme.primary : Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private func newCardForm(_ p: CheckoutProduct) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GwField(label: "Número do cartão", erro: model.fieldErrors["number"]) {
                HStack(spacing: 8) {
                    TextField("0000 0000 0000 0000", text: Binding(
                        get: { model.cardNumber },
                        set: { model.cardNumber = CheckoutFormat.maskCard($0) }
                    ))
                    .keyboardType(.numberPad)
                    .textContentType(.creditCardNumber)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("cardNumber")
                    if let marca = CardBrand.detect(model.cardNumber) {
                        CardBrandBadge(brand: marca)
                    }
                    if CheckoutFormat.digits(model.cardNumber).count >= 13 {
                        Image(systemName: CheckoutFormat.luhn(model.cardNumber) ? "checkmark" : "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(CheckoutFormat.luhn(model.cardNumber) ? Theme.success : Theme.danger)
                    }
                }
            }
            GwField(label: "Nome impresso no cartão", erro: model.fieldErrors["holderName"]) {
                TextField("Como está no cartão", text: $model.holderName)
                    .textContentType(.name)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("cardHolder")
            }
            HStack(alignment: .top, spacing: 12) {
                GwField(label: "Validade", erro: model.fieldErrors["expiry"]) {
                    TextField("MM/AA", text: Binding(
                        get: { model.expiry },
                        set: { model.expiry = CheckoutFormat.maskExpiry($0) }
                    ))
                    .keyboardType(.numberPad)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("cardExpiry")
                }
                GwField(label: "CVV", erro: model.fieldErrors["ccv"]) {
                    TextField("123", text: Binding(
                        get: { model.ccv },
                        set: { model.ccv = String(CheckoutFormat.digits($0).prefix(4)) }
                    ))
                    .keyboardType(.numberPad)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("cardCvv")
                }
            }
            HStack(alignment: .top, spacing: 12) {
                GwField(label: "CEP da fatura", erro: model.fieldErrors["postalCode"]) {
                    TextField("00000-000", text: Binding(
                        get: { model.postalCode },
                        set: { model.postalCode = CheckoutFormat.maskCep($0) }
                    ))
                    .keyboardType(.numberPad)
                    .textContentType(.postalCode)
                    .accessibilityIdentifier("cardCep")
                }
                GwField(label: "Número", erro: model.fieldErrors["addressNumber"]) {
                    TextField("123", text: $model.addressNumber)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("cardAddressNumber")
                }
            }
            if p.cartaoSalvo.ligado {
                if model.cardLimitReached {
                    note(
                        "Você já tem \(p.cartaoSalvo.maxCartoes) cartões salvos, o máximo. Para salvar este, remova um em Créditos.",
                        color: Theme.textSecondary,
                        background: Theme.background
                    )
                } else {
                    Button {
                        Haptics.tap()
                        model.saveCard.toggle()
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: model.saveCard ? "checkmark.square.fill" : "square")
                                .font(.system(size: 19))
                                .foregroundStyle(model.saveCard ? Theme.primary : Theme.textSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Salvar este cartão para as próximas compras")
                                    .font(Theme.body(14, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .multilineTextAlignment(.leading)
                                Text("Fica guardado só um código seguro do Asaas, nunca o número. Na próxima, é só confirmar sua senha.")
                                    .font(Theme.body(11))
                                    .foregroundStyle(Theme.textSecondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressableSubtle)
                    .accessibilityIdentifier("saveCardToggle")
                    .accessibilityAddTraits(model.saveCard ? .isSelected : [])
                }
            }
        }
    }

    private func installmentLabel(_ p: CheckoutInstallment) -> String {
        "\(p.installments)x de \(CheckoutFormat.cents(p.installmentCents))"
            + (p.installments == 1 ? " à vista" : " · total \(CheckoutFormat.cents(p.totalCents))")
    }

    private func pct(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    // MARK: Resumo

    private var summaryCard: some View {
        ThemeCard(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("RESUMO")
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                ForEach(Array((model.quote?.items ?? [model.product!.product]).enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.title + (item.leadsQty > 0 ? " · \(item.leadsQty)" : ""))
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(CheckoutFormat.cents(item.unitPriceCents))
                            .font(Theme.body(14, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                if let c = model.quote?.coupon {
                    HStack {
                        Text("Cupom \(c.code)")
                        Spacer()
                        Text("− \(CheckoutFormat.cents(c.discountCents))")
                    }
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.success)
                }
                if model.method == .creditCard, let c = model.chosenInstallment, c.surchargeCents > 0 {
                    HStack {
                        Text("Acréscimo \(c.installments)x")
                        Spacer()
                        Text(CheckoutFormat.cents(c.surchargeCents))
                    }
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                }
                Divider().overlay(Theme.border)
                couponRow
            }
        }
    }

    @State private var couponOpen = false

    @ViewBuilder
    private var couponRow: some View {
        if model.quote?.coupon != nil {
            Button("Remover cupom") {
                Haptics.tap()
                model.removeCoupon()
                couponOpen = false
            }
            .font(Theme.body(13))
            .foregroundStyle(Theme.textSecondary)
        } else if !couponOpen {
            Button("Tem um cupom?") {
                Haptics.tap()
                couponOpen = true
            }
            .font(Theme.body(14, weight: .semibold))
            .foregroundStyle(Theme.primary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TextField("CÓDIGO", text: Binding(
                        get: { model.couponInput },
                        set: { model.couponInput = $0.uppercased() }
                    ))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(Theme.body(14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                    Button {
                        Haptics.tap()
                        model.applyCoupon()
                    } label: {
                        ZStack {
                            Text("Aplicar").opacity(model.isQuoting && model.coupon != nil ? 0 : 1)
                            if model.isQuoting && model.coupon != nil { ProgressView().controlSize(.small) }
                        }
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                    .disabled(model.couponInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if model.coupon != nil, let erro = model.quote?.couponError {
                    Text(erro).font(Theme.body(12)).foregroundStyle(Theme.danger)
                }
            }
        }
    }

    private func guarantee(_ texto: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 18))
                .foregroundStyle(Theme.success)
            VStack(alignment: .leading, spacing: 3) {
                Text("Garantia")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(texto)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.successSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    // MARK: Barra de pagar

    private var payBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.border)
            VStack(spacing: 10) {
                if let erro = model.submitError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(erro)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if model.suggestPix || model.suggestOtherCard || model.disconnected {
                            HStack(spacing: 8) {
                                if model.suggestPix {
                                    suggestion("Pagar com Pix", icon: "qrcode", filled: true) { model.switchToPix() }
                                }
                                if model.suggestOtherCard {
                                    suggestion("Usar outro cartão", icon: "creditcard", filled: false) { model.useOtherCard() }
                                }
                                if model.disconnected {
                                    NavigationLink("Conectar meus leads") { LeadsListView() }
                                        .font(Theme.body(13, weight: .semibold))
                                        .foregroundStyle(Theme.primary)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: 12))
                    .transition(.opacity)
                }
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Total")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                        if let total = model.totalCents {
                            Text(CheckoutFormat.cents(total))
                                .font(Theme.moneyDisplay(22))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                                .contentTransition(.numericText())
                                .accessibilityIdentifier("checkoutTotal")
                        } else {
                            SkeletonBlock(width: 110, height: 24)
                        }
                        if model.method == .creditCard, let c = model.chosenInstallment, c.installments > 1 {
                            Text("\(c.installments)x de \(CheckoutFormat.cents(c.installmentCents))")
                                .font(Theme.body(11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer()
                    if model.leadsInOrder > 0 {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("Você recebe")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                            Text("\(model.leadsInOrder) contatos")
                                .font(Theme.body(16, weight: .bold))
                                .foregroundStyle(Theme.success)
                        }
                    }
                }
                PrimaryButton(
                    title: model.payTitle,
                    icon: model.method == .pix ? "qrcode" : model.method == .boleto ? "barcode" : "lock.fill",
                    isLoading: model.isSubmitting,
                    isEnabled: model.quote != nil
                ) {
                    Task { await model.pay() }
                }
                .accessibilityIdentifier("payButton")
                HStack(spacing: 5) {
                    Image(systemName: "lock.shield").font(.system(size: 10))
                    Text("Processado pelo Asaas · ambiente seguro")
                }
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Theme.surface)
            .animation(.easeInOut(duration: 0.2), value: model.submitError)
        }
    }

    private func suggestion(_ title: String, icon: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(filled ? .white : Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(filled ? Theme.primary : Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(filled ? .clear : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Order bump

private struct OrderBumpCard: View {
    let offer: CheckoutItem
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        let desconto = offer.onSale ? Int(((1 - Double(offer.unitPriceCents) / Double(offer.priceCents)) * 100).rounded()) : 0
        VStack(spacing: 0) {
            Text((offer.sectionLabel ?? "Oferta especial").uppercased())
                .font(Theme.body(10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(isOn ? Theme.success : Theme.warning)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(isOn ? Theme.successSoft : Theme.warningSoft)
            Button {
                Haptics.tap()
                toggle()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isOn ? "checkmark.square.fill" : "square")
                        .font(.system(size: 20))
                        .foregroundStyle(isOn ? Theme.success : Theme.warning)
                    VStack(alignment: .leading, spacing: 4) {
                        (Text("\(offer.headline ?? offer.title): ").font(Theme.body(14, weight: .bold))
                            + Text(isOn ? "adicionado por mais " : "adicione por mais ").font(Theme.body(14)).foregroundColor(Theme.textSecondary)
                            + Text(CheckoutFormat.cents(offer.unitPriceCents)).font(Theme.body(14, weight: .bold)))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            if offer.onSale {
                                Text(CheckoutFormat.cents(offer.priceCents))
                                    .strikethrough()
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            if desconto > 0 {
                                StatusBadge(label: "−\(desconto)%", color: Theme.success, background: Theme.successSoft)
                            }
                        }
                        Text(offer.leadsQty > 0
                             ? "+\(offer.leadsQty) contatos · \(CheckoutFormat.cents(offer.unitPriceCents / max(1, offer.leadsQty))) por contato"
                             : (offer.description ?? "Adicione à sua compra"))
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(isOn ? Theme.successSoft.opacity(0.4) : Theme.surface)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)
            .accessibilityAddTraits(isOn ? .isSelected : [])
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(isOn ? Theme.success.opacity(0.6) : Theme.warning.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        )
        .animation(.easeInOut(duration: 0.18), value: isOn)
    }
}

// MARK: - Perguntas frequentes

private struct FAQCard: View {
    let items: [CheckoutItem.FAQ]
    @State private var open: Int?

    var body: some View {
        ThemeCard(padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Perguntas frequentes")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.bottom, 6)
                ForEach(Array(items.enumerated()), id: \.offset) { i, f in
                    if i > 0 { Divider().overlay(Theme.border) }
                    Button {
                        Haptics.tap()
                        withAnimation(.easeInOut(duration: 0.2)) { open = open == i ? nil : i }
                    } label: {
                        HStack {
                            Text(f.q)
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.textPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .rotationEffect(.degrees(open == i ? 180 : 0))
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if open == i {
                        Text(f.a)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Senha do app para o cartão salvo

private struct PasswordConfirmSheet: View {
    let model: LeadsCheckoutModel
    @State private var senha = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Confirme sua senha")
                    .font(Theme.serifTitle(22))
                    .foregroundStyle(Theme.textPrimary)
                if let c = model.cardInUse {
                    Text("Para pagar com o \(c.title).")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            GwField(
                label: "Senha do app",
                hint: "É a mesma senha que você usa para entrar aqui. Vale por 15 minutos.",
                erro: model.passwordError
            ) {
                SecureField("Sua senha", text: $senha)
                    .textContentType(.password)
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit { Task { await model.confirmPassword(senha) } }
                    .accessibilityIdentifier("stepUpPassword")
            }
            PrimaryButton(title: "Confirmar e pagar", icon: "lock.fill", isLoading: model.isConfirmingPassword) {
                Task { await model.confirmPassword(senha) }
            }
            .accessibilityIdentifier("stepUpConfirm")
            Button("Cancelar") { model.cancelPassword() }
                .font(Theme.body(14, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .disabled(model.isConfirmingPassword)
        }
        .padding(Theme.screenPadding)
        .onAppear { focused = true }
        .onChange(of: model.passwordError) { _, erro in
            if erro != nil { senha = "" }
        }
    }
}
