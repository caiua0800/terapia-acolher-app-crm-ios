import SwiftUI

/// Depois de pedir: Pix com QR e copia-e-cola (consulta a cada 4 s enquanto
/// pendente e a tela estiver aberta), boleto com linha digitável, cartão em
/// análise ou o resultado. Quando pago, saldo e Início se atualizam.
struct LeadsOrderView: View {
    let orderId: Int
    var initial: LeadsOrder?
    /// Embutida no checkout, quem põe o título na barra é o checkout.
    var showsTitle = true

    @State private var order: LeadsOrder?
    @State private var errorMessage: String?
    @State private var isRetrying = false
    @State private var confirmCancel = false
    @State private var isCanceling = false
    @State private var alerta: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content
        }
        .modifier(OrderTitle(show: showsTitle))
        .task(id: orderId) { await poll() }
        .confirmationDialog("Cancelar este pedido?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancelar pedido", role: .destructive) { Task { await cancel() } }
            Button("Voltar", role: .cancel) {}
        } message: {
            Text(order?.paymentMethod == "pix"
                 ? "O Pix deixa de valer. Se você já pagou, não cancele: a confirmação chega em instantes."
                 : "O boleto deixa de valer. Se você já pagou, não cancele: a compensação leva até 1 dia útil.")
        }
        .alert("Não deu certo", isPresented: Binding(get: { alerta != nil }, set: { if !$0 { alerta = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alerta ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let o = order {
            ScrollView {
                VStack(spacing: 16) {
                    if o.isPaid {
                        paid(o)
                    } else if o.isPending {
                        switch o.paymentMethod {
                        case "pix": pixPending(o)
                        case "boleto": boletoPending(o)
                        default: cardReview(o)
                        }
                    } else {
                        notCompleted(o)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .animation(.easeInOut(duration: 0.25), value: o.status)
            }
        } else if let errorMessage {
            VStack(spacing: 16) {
                Text(errorMessage)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                RetryButton(isLoading: isRetrying) {
                    Task {
                        isRetrying = true
                        await fetch()
                        isRetrying = false
                    }
                }
            }
        } else {
            VStack(spacing: 14) {
                SkeletonBlock(height: 360, cornerRadius: Theme.cornerRadius)
            }
            .padding(.horizontal, Theme.screenPadding)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 8)
        }
    }

    // MARK: Consulta

    /// Enquanto a tela está aberta e o pedido pendente, consulta a cada 4 s.
    /// Sair da tela cancela a `task` e o laço para sozinho.
    private func poll() async {
        if order == nil, let initial { order = initial }
        if order == nil { await fetch() }
        while !Task.isCancelled, order?.isPending == true {
            try? await Task.sleep(for: .seconds(4))
            if Task.isCancelled { break }
            await fetch()
        }
        // Pago (na hora, no cartão, ou depois, no Pix): saldo e Início se
        // atualizam — o saldo mora no status dos leads.
        if order?.isPaid == true, !Task.isCancelled {
            await LeadsStore.shared.load()
        }
    }

    @MainActor
    private func fetch() async {
        do {
            let novo = try await LeadsCheckoutAPI.order(orderId)
            if order?.isPending == true, novo.isPaid { Haptics.success() }
            order = novo
            errorMessage = nil
        } catch is CancellationError {
        } catch let e as APIError {
            if order == nil { errorMessage = e.message }
        } catch {
            if order == nil { errorMessage = "Não foi possível carregar o pedido." }
        }
    }

    @MainActor
    private func cancel() async {
        isCanceling = true
        defer { isCanceling = false }
        do {
            try await LeadsCheckoutAPI.cancel(orderId)
            await fetch()
        } catch let e as APIError {
            alerta = e.message
            await fetch()
        } catch {
            alerta = "Não foi possível cancelar agora."
        }
    }

    // MARK: Peças

    private func items(_ o: LeadsOrder) -> some View {
        VStack(spacing: 8) {
            Divider().overlay(Theme.border)
            ForEach(Array(o.items.enumerated()), id: \.offset) { _, i in
                HStack {
                    Text(i.title + (i.leadsQty > 0 ? " · \(i.leadsQty)" : ""))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(CheckoutFormat.cents(i.unitPriceCents)).foregroundStyle(Theme.textPrimary)
                }
            }
            if o.discountCents > 0 {
                HStack {
                    Text("Cupom \(o.couponCode ?? "")")
                    Spacer()
                    Text("− \(CheckoutFormat.cents(o.discountCents))")
                }
                .foregroundStyle(Theme.success)
            }
            if o.surchargeCents > 0 {
                HStack {
                    Text("Acréscimo \(o.installments)x")
                    Spacer()
                    Text(CheckoutFormat.cents(o.surchargeCents))
                }
                .foregroundStyle(Theme.textSecondary)
            }
            Divider().overlay(Theme.border)
            HStack {
                Text("Total").fontWeight(.semibold)
                Spacer()
                Text(CheckoutFormat.cents(o.totalCents)).fontWeight(.semibold)
            }
            .foregroundStyle(Theme.textPrimary)
        }
        .font(Theme.body(14))
    }

    private func waiting(_ texto: String) -> some View {
        HStack(spacing: 8) {
            PulsingDot()
            Text(texto)
                .font(Theme.body(13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var cancelButton: some View {
        Button {
            Haptics.tap()
            confirmCancel = true
        } label: {
            HStack(spacing: 6) {
                if isCanceling { ProgressView().controlSize(.small) }
                Text("Cancelar pedido")
            }
            .font(Theme.body(14, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.pressable)
        .disabled(isCanceling)
    }

    private func header(_ label: String, _ o: LeadsOrder, sub: String?) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(Theme.body(10, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(Theme.textSecondary)
            Text(CheckoutFormat.cents(o.totalCents))
                .font(Theme.moneyDisplay(30))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            if let sub {
                Text(sub)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Estados

    private func pixPending(_ o: LeadsOrder) -> some View {
        ThemeCard(padding: 20) {
            VStack(spacing: 18) {
                header("PAGUE COM PIX", o, sub: o.leadsQty > 0 ? "\(o.leadsQty) contatos assim que pagar" : nil)
                if let codigo = o.pixPayload {
                    GwQRCodeView(payload: codigo, size: 210)
                    GwCopyButton(title: "Copiar código Pix", value: codigo)
                        .accessibilityIdentifier("copyPix")
                    Text(codigo)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Text("O código Pix não veio agora. Cancele e gere de novo.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.warning)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Abra o app do seu banco e escolha Pix copia e cola ou ler QR code.")
                    Text("2. Confira o valor e pague.")
                    Text("3. Esta tela confirma sozinha, em segundos.")
                }
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                waiting("Aguardando o pagamento")
                items(o)
                cancelButton
            }
        }
    }

    private func boletoPending(_ o: LeadsOrder) -> some View {
        ThemeCard(padding: 20) {
            VStack(spacing: 16) {
                header(
                    "BOLETO GERADO",
                    o,
                    sub: CheckoutFormat.date(o.boletoDueDate).map { "Vence em \(CheckoutFormat.dayMonthYear.string(from: $0))" }
                )
                if let linha = o.boletoLine {
                    Text(linha)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                    GwCopyButton(title: "Copiar linha digitável", value: linha)
                }
                if let url = (o.boletoUrl ?? o.invoiceUrl).flatMap(URL.init(string:)) {
                    SecondaryButton(title: "Abrir boleto", icon: "arrow.up.right.square") { openURL(url) }
                }
                Text("Os contatos entram quando o banco compensar, em até 1 dia útil. Você pode fechar esta tela.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                items(o)
                cancelButton
            }
        }
    }

    private func cardReview(_ o: LeadsOrder) -> some View {
        ThemeCard(padding: 20) {
            VStack(spacing: 14) {
                Image(systemName: "clock")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.warning)
                    .frame(width: 56, height: 56)
                    .background(Theme.warningSoft, in: Circle())
                Text("Pagamento em análise")
                    .font(Theme.serifTitle(22))
                    .foregroundStyle(Theme.textPrimary)
                Text("A operadora do cartão está conferindo a compra. Costuma levar poucos minutos; os contatos entram assim que aprovar.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                waiting("Conferindo com a operadora")
                items(o)
            }
        }
    }

    private func paid(_ o: LeadsOrder) -> some View {
        ThemeCard(padding: 22) {
            VStack(spacing: 14) {
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.success)
                    .frame(width: 64, height: 64)
                    .background(Theme.successSoft, in: Circle())
                Text("Pagamento confirmado")
                    .font(Theme.serifTitle(24))
                    .foregroundStyle(Theme.textPrimary)
                Text(o.leadsQty > 0 ? "\(o.leadsQty) contatos entraram no seu saldo." : "Sua compra foi confirmada.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                if let saldo = o.currentBalance {
                    VStack(spacing: 2) {
                        Text("SALDO ATUAL")
                            .font(Theme.body(10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.primary.opacity(0.8))
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(saldo)")
                                .font(Theme.moneyDisplay(30))
                                .foregroundStyle(Theme.primary)
                            Text(saldo == 1 ? "crédito" : "créditos")
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.primary.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 14))
                }
                items(o)
                Text(paidDetail(o))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                NavigationLink {
                    LeadsListView()
                } label: {
                    Label("Ver meus leads", systemImage: "tray.full")
                        .font(Theme.body(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.primary, in: RoundedRectangle(cornerRadius: 26))
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private func paidDetail(_ o: LeadsOrder) -> String {
        var partes: [String] = []
        if o.paymentMethod == "credit_card", let last = o.cardLast4 {
            partes.append("\(CardBrand.displayName(o.cardBrand)) final \(last)" + (o.installments > 1 ? " · \(o.installments)x" : ""))
        } else {
            partes.append(o.paymentMethod == "pix" ? "Pago com Pix" : "Pago com boleto")
        }
        if let d = CheckoutFormat.date(o.paidAt) { partes.append(CheckoutFormat.dayTime.string(from: d)) }
        return partes.joined(separator: " · ")
    }

    private func notCompleted(_ o: LeadsOrder) -> some View {
        ThemeCard(padding: 22) {
            VStack(spacing: 14) {
                StatusBadge(
                    label: o.statusLabel.uppercased(),
                    color: o.status == "failed" ? Theme.danger : Theme.textSecondary,
                    background: o.status == "failed" ? Theme.dangerSoft : Theme.border.opacity(0.6)
                )
                Text(o.status == "failed" ? "O pagamento não foi aprovado" : "Este pedido não está mais valendo")
                    .font(Theme.serifTitle(22))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Nada foi cobrado por ele. Você pode fazer uma nova compra quando quiser.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                items(o)
                if let pid = o.mainProductId {
                    NavigationLink {
                        LeadsCheckoutView(productId: pid)
                    } label: {
                        Text("Comprar de novo")
                            .font(Theme.body(16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 26))
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }
}

/// Ponto verde pulsando: "estamos esperando", sem spinner girando sem fim.
private struct PulsingDot: View {
    @State private var on = false

    var body: some View {
        ZStack {
            Circle().fill(Theme.primary.opacity(0.35))
                .frame(width: 10, height: 10)
                .scaleEffect(on ? 2 : 1)
                .opacity(on ? 0 : 1)
            Circle().fill(Theme.primary).frame(width: 10, height: 10)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { on = true }
        }
    }
}

private struct OrderTitle: ViewModifier {
    let show: Bool

    func body(content: Content) -> some View {
        if show {
            content
                .setToolbarTitle("Pedido")
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }
}
