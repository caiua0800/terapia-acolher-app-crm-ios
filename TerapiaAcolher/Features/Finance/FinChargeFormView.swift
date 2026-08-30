import SwiftUI

/// Sheet de nova cobrança pro paciente.
struct FinChargeFormView: View {
    let patient: FinPatientRef
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var descriptionText = ""
    @State private var amountText = ""
    @State private var dueDate = Date()
    @State private var referenceMonthDate = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Vem do servidor: taxa, valor mínimo e quais métodos existem hoje.
    @State private var fees: FinFees?
    /// Recalculado a cada mudança de valor: a taxa do cartão é percentual.
    @State private var quote: FinQuote?
    @State private var quoteTask: Task<Void, Never>?
    /// Liga NO INSTANTE do toque/digitação, antes do debounce e da rede. Sem
    /// isso o bloco do líquido some e reaparece do nada — o mesmo problema que
    /// a busca de pacientes já tinha.
    @State private var calculando = false
    @State private var metodoId = "PIX"
    /// Cobrança combinada fora do app (dinheiro, transferência direta) não
    /// passa pelo gateway e não tem taxa — por isso a escolha é explícita.
    @State private var online = true

    /// Cobrança criada, com o link já gerado. Leva direto para o link em vez de
    /// só fechar a tela: criar e não ter o que mandar ao paciente deixava o
    /// terapeuta no meio do caminho.
    @State private var recemCriada: FinCheckoutResult?

    private var valor: Double? { FinFormat.parseAmount(amountText) }

    /// O que cai na conta do terapeuta, calculado pelo SERVIDOR para o método
    /// escolhido. Uma taxa só, somada — ele não precisa saber que ela se
    /// divide entre gateway, antecipação e plataforma.
    private var linhaDoMetodo: FinQuote.Metodo? {
        guard online else { return nil }
        return quote?.metodo(metodoId)
    }

    private var minimo: Double { quote?.minOnlineCharge ?? fees?.minOnlineCharge ?? 5 }

    private var abaixoDoMinimo: Bool {
        guard online, let valor else { return false }
        return valor > 0 && valor < minimo
    }

    private var isValid: Bool {
        guard !descriptionText.trimmingCharacters(in: .whitespaces).isEmpty,
              let amount = FinFormat.parseAmount(amountText), amount > 0
        else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            InitialAvatar(name: patient.name, size: 40)
                            Text(patient.name)
                                .font(Theme.body(16, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }

                        fieldCard("Descrição") {
                            TextField("Ex.: Cobrança de julho", text: $descriptionText)
                                .font(Theme.body(15))
                        }

                        fieldCard("Valor (R$)") {
                            TextField("0,00", text: $amountText)
                                .font(Theme.money(17))
                                .keyboardType(.decimalPad)
                        }

                        formaDeRecebimento
                        resumoDoLiquido
                            .animation(.easeOut(duration: 0.2), value: metodoId)
                            .animation(.easeOut(duration: 0.2), value: online)

                        ThemeCard {
                            DatePicker("Vencimento", selection: $dueDate, displayedComponents: .date)
                                .font(Theme.body(15, weight: .semibold))
                                .tint(Theme.primary)
                                .environment(\.locale, Locale(identifier: "pt_BR"))
                        }

                        ThemeCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Mês de referência")
                                        .font(Theme.body(15, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(FinFormat.monthTitleText(referenceMonthDate))
                                        .font(Theme.body(13))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                monthStepButton("chevron.left", delta: -1)
                                monthStepButton("chevron.right", delta: 1)
                            }
                        }

                        PrimaryButton(title: "Criar cobrança", isLoading: isSaving, isEnabled: isValid) {
                            Task { await save() }
                        }
                        .padding(.top, 4)
                    }
                    .padding(Theme.screenPadding)
                }
            }
            .navigationTitle("Nova cobrança")
            .navigationBarTitleDisplayMode(.inline)
            // Taxa e métodos vêm do servidor. Se a chamada falhar, o resumo do
            // líquido simplesmente não aparece — melhor não mostrar nada do que
            // mostrar um número que pode estar errado.
            .task { fees = try? await FinanceAPI.fees() }
            // A taxa do cartão é percentual, então o líquido muda com o valor.
            // Debounce curto: sem ele, cada tecla digitada viraria requisição.
            .onChange(of: amountText) { _, _ in
                quoteTask?.cancel()
                guard let valor, valor > 0 else {
                    quote = nil
                    calculando = false
                    return
                }
                calculando = true
                quoteTask = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled else { return }
                    let novo = try? await FinanceAPI.quote(amount: valor)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        quote = novo
                        calculando = false
                    }
                }
            }
            .sheet(item: $recemCriada) { resultado in
                FinChargeLinkSheet(result: resultado, patientName: patient.name) {
                    recemCriada = nil
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .alert("Ops", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                if descriptionText.isEmpty {
                    let month = FinFormat.monthTitle.string(from: Date())
                        .components(separatedBy: " de ").first ?? ""
                    descriptionText = "Cobrança de \(month)"
                }
            }
        }
    }

    private func monthStepButton(_ icon: String, delta: Int) -> some View {
        Button {
            if let next = Calendar.current.date(byAdding: .month, value: delta, to: referenceMonthDate) {
                referenceMonthDate = next
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 30, height: 30)
                .background(Theme.background, in: Circle())
                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
        }
    }

    private func fieldCard(_ label: String, @ViewBuilder content: @escaping () -> some View) -> some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(label.uppercased())
                    .font(Theme.body(11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textSecondary)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }


    // MARK: - Forma de recebimento

    private var formaDeRecebimento: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMO VOCÊ VAI RECEBER")
                .font(Theme.body(10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 2)

            ThemeCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(fees?.methods ?? []) { metodo in
                        opcao(
                            titulo: metodo.label,
                            subtitulo: metodo.description,
                            icone: metodo.id == "PIX" ? "qrcode" : "creditcard",
                            marcado: online && metodoId == metodo.id,
                            habilitado: metodo.available
                        ) {
                            online = true
                            metodoId = metodo.id
                        }
                        Divider().overlay(Theme.border)
                    }

                    // Recebimento por fora não passa pelo gateway: sem link,
                    // sem taxa. Existe porque muita sessão é paga em dinheiro
                    // ou por transferência direta, e a cobrança serve só de
                    // controle.
                    opcao(
                        titulo: "Combinar por fora",
                        subtitulo: "Dinheiro, transferência — sem taxa",
                        icone: "hand.raised",
                        marcado: !online,
                        habilitado: true
                    ) {
                        online = false
                    }
                }
            }
        }
    }

    private func opcao(
        titulo: String,
        subtitulo: String,
        icone: String,
        marcado: Bool,
        habilitado: Bool,
        acao: @escaping () -> Void
    ) -> some View {
        Button {
            guard habilitado else { return }
            withAnimation(.easeOut(duration: 0.15)) { acao() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icone)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(marcado ? Theme.primary : Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(
                        marcado ? Theme.primarySoft : Theme.background,
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo)
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitulo)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: marcado ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(marcado ? Theme.primary : Theme.border)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .opacity(habilitado ? 1 : 0.45)
        }
        .buttonStyle(.pressableSubtle)
        .disabled(!habilitado)
    }

    // MARK: - Quanto entra na conta

    @ViewBuilder
    private var resumoDoLiquido: some View {
        if abaixoDoMinimo {
            ThemeCard {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warning)
                    Text("Cobrança online a partir de \(Formatters.brl(minimo)). Abaixo disso, combine por fora.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if calculando, let valor, valor > 0 {
            // Esqueleto no formato exato do resumo: quando o número chega, é
            // troca de conteúdo, não a caixa inteira aparecendo de repente.
            ThemeCard {
                VStack(spacing: 10) {
                    linha("Valor da cobrança", Formatters.brl(valor), destaque: false)
                    HStack {
                        Text("Taxa do sistema")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        SkeletonBlock(width: 62, height: 13)
                    }
                    Divider().overlay(Theme.border)
                    HStack {
                        Text("Você recebe")
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        SkeletonBlock(width: 104, height: 22, cornerRadius: 8)
                    }
                }
            }
            .transition(.opacity)
        } else if let m = linhaDoMetodo, let valor, valor > 0 {
            ThemeCard {
                VStack(spacing: 10) {
                    linha("Valor da cobrança", Formatters.brl(valor), destaque: false)
                    linha("Taxa do sistema", "− \(Formatters.brl(m.fee))", destaque: false)
                    Divider().overlay(Theme.border)
                    linha("Você recebe", Formatters.brl(m.net), destaque: true)
                    // Prazo junto do valor, sempre. "Você recebe R$ X" sem
                    // dizer QUANDO vira promessa falsa no cartão, que leva 32
                    // dias sem antecipação.
                    HStack {
                        Spacer()
                        Text(m.daysToReceive == 0 ? "na sua conta na hora" : "na sua conta em 1 dia útil")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private func linha(_ rotulo: String, _ valor: String, destaque: Bool) -> some View {
        HStack {
            Text(rotulo)
                .font(Theme.body(destaque ? 15 : 13, weight: destaque ? .semibold : .regular))
                .foregroundStyle(destaque ? Theme.textPrimary : Theme.textSecondary)
            Spacer()
            Text(valor)
                .font(destaque ? Theme.moneyDisplay(19) : Theme.money(14))
                .monospacedDigit()
                .foregroundStyle(destaque ? Theme.success : Theme.textSecondary)
        }
    }

    private func save() async {
        guard let amount = FinFormat.parseAmount(amountText) else { return }
        isSaving = true
        defer { isSaving = false }
        let body = FinChargeBody(
            patientId: patient.id,
            description: descriptionText.trimmingCharacters(in: .whitespaces),
            amount: amount,
            dueDate: FinFormat.isoDay.string(from: dueDate),
            referenceMonth: FinFormat.monthQuery.string(from: referenceMonthDate),
            intendedBillingType: online ? metodoId : nil
        )
        do {
            let criada = try await FinanceAPI.createCharge(body)
            onSaved()
            guard online else {
                dismiss()
                return
            }
            // Gera o link na sequência. Criar a cobrança e não ter o que mandar
            // ao paciente deixava o terapeuta no meio do caminho: ele tinha que
            // achar a cobrança na lista e só então pedir o link.
            do {
                recemCriada = try await FinanceAPI.checkout(
                    id: criada.id,
                    billingType: metodoId
                )
                Haptics.success()
            } catch {
                // A cobrança FOI criada. Tratar como erro genérico faria ele
                // criar tudo de novo e ficar com duas.
                errorMessage = (error as? APIError).map {
                    "Cobrança criada, mas o link não foi gerado: \($0.message)"
                } ?? "Cobrança criada, mas o link não foi gerado. Você pode gerá-lo abrindo a cobrança."
            }
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível criar a cobrança."
        }
    }
}
