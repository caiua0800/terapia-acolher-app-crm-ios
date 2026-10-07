import SwiftUI

/// Sheet de nova cobrança: para um paciente ou, desde 2026-10-06, para outra
/// pessoa (cobrança avulsa — supervisão, curso, sala; não vira paciente).
struct FinChargeFormView: View {
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// Paciente | Outra pessoa. Começa em paciente quando a tela de origem já
    /// tem um (ficha, cobranças do paciente).
    @State private var paraPaciente: Bool
    @State private var paciente: FinPatientRef?
    @State private var escolhendoPaciente = false

    // Pagador avulso: só o mínimo que o Asaas exige para gerar Pix/cartão.
    @State private var nomePagador = ""
    @State private var documentoPagador = ""
    @State private var emailPagador = ""

    // Avisar o paciente (só paciente: o número oficial só fala com quem está
    // cadastrado, o que protege a reputação dele para todos os terapeutas).
    @State private var enviarAgora = false
    @State private var agendarLembrete = false
    @State private var dataDoLembrete: Date
    /// Enquanto o terapeuta não mexer na hora do lembrete, ela acompanha o
    /// vencimento (dia do vencimento às 9h).
    @State private var lembreteTocado = false
    /// O que aconteceu com o envio/agendamento, mostrado na folha do Pix.
    @State private var avisoDoEnvio: FinAvisoDeEnvio?

    init(patient: FinPatientRef?, onSaved: @escaping () -> Void) {
        self.onSaved = onSaved
        _paraPaciente = State(initialValue: patient != nil)
        _paciente = State(initialValue: patient)
        _dataDoLembrete = State(initialValue: Self.noveDaManha(de: Date()))
    }

    @State private var descriptionText = ""
    @State private var amountText = ""
    @State private var dueDate = Date()
    @State private var referenceMonthDate = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Só o Acolher Financeiro cobra: taxas e mínimo vêm de lá (do servidor —
    /// a taxa nunca é cravada no app).
    @State private var store = FinGatewayStore.shared
    /// Pix do gateway gerado logo após criar. Criar e não ter o que mandar ao
    /// paciente deixava o terapeuta no meio do caminho.
    @State private var pixCriado: GwCharge?
    /// Fecha o sheet quando o Pix for fechado (a cobrança já existe).
    @State private var fecharAoFecharPix = false
    /// Pix ou cartão (2026-10-06). O cartão só aparece se o servidor liberar.
    @State private var noCartao = false
    /// Repassar as taxas do cartão ao paciente. Começa com a preferência da
    /// conta; `nil` = ainda não mexeu aqui.
    @State private var repassarEscolhido: Bool?

    private var cartao: GwCardFees? {
        guard let card = taxas?.card, card.available else { return nil }
        return card
    }
    private var usandoCartao: Bool { noCartao && cartao != nil }
    private var repassar: Bool {
        repassarEscolhido ?? store.account?.cardFeesPassThrough ?? false
    }

    private var valor: Double? { FinFormat.parseAmount(amountText) }

    private var taxas: GwFees? { store.overview?.fees }
    private var podeCobrarPorPix: Bool { store.isApproved }

    private var minimo: Double { taxas?.minCharge ?? 5 }

    private var abaixoDoMinimo: Bool {
        guard podeCobrarPorPix, let valor else { return false }
        return valor > 0 && valor < minimo
    }

    private var digitosDoDocumento: String { documentoPagador.filter(\.isNumber) }

    private var documentoValido: Bool {
        let d = digitosDoDocumento
        return d.count == 11 ? GwDocumentoValido.cpf(d) : GwDocumentoValido.cnpj(d)
    }

    private var emailPagadorValido: Bool {
        let e = emailPagador.trimmingCharacters(in: .whitespaces)
        return e.isEmpty || (e.contains("@") && e.contains(".") && !e.contains(" "))
    }

    private var destinatarioValido: Bool {
        if paraPaciente { return paciente != nil }
        return nomePagador.trimmingCharacters(in: .whitespaces).count >= 2
            && documentoValido && emailPagadorValido
    }

    /// Por que o WhatsApp não pode sair para este paciente (nil = pode).
    private var motivoSemWhatsApp: String? {
        guard let paciente else { return nil }
        if (paciente.whatsapp ?? "").filter(\.isNumber).isEmpty {
            return "\(primeiroNome(paciente.name)) não tem WhatsApp cadastrado."
        }
        if paciente.whatsappEnabled == false {
            return "As mensagens por WhatsApp estão desligadas para \(primeiroNome(paciente.name))."
        }
        return nil
    }

    /// Desde 2026-09-23 não existe cobrança "por fora": sem conta aprovada no
    /// Acolher Financeiro não dá pra criar cobrança.
    private var isValid: Bool {
        guard podeCobrarPorPix, !abaixoDoMinimo, destinatarioValido,
              !descriptionText.trimmingCharacters(in: .whitespaces).isEmpty,
              let amount = FinFormat.parseAmount(amountText), amount > 0
        else { return false }
        if paraPaciente, agendarLembrete, dataDoLembrete <= Date() { return false }
        return true
    }

    private func primeiroNome(_ nome: String) -> String {
        nome.split(separator: " ").first.map(String.init) ?? nome
    }

    /// Dia `data` às 9h (hora local).
    private static func noveDaManha(de data: Date) -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: data) ?? data
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        destinatario

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
                            .animation(.easeOut(duration: 0.2), value: valor)

                        ThemeCard {
                            DatePicker("Vencimento", selection: $dueDate, displayedComponents: .date)
                                .font(Theme.body(15, weight: .semibold))
                                .tint(Theme.primary)
                                .environment(\.locale, Locale(identifier: "pt_BR"))
                        }
                        .onChange(of: dueDate) { _, novo in
                            if !lembreteTocado { dataDoLembrete = Self.noveDaManha(de: novo) }
                        }

                        if paraPaciente {
                            avisarPaciente
                        } else {
                            Text("Você envia o link de pagamento por onde quiser.")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.leading, 2)
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

                        PrimaryButton(
                            title: usandoCartao ? "Criar e gerar link do cartão" : "Criar e gerar Pix",
                            isLoading: isSaving,
                            isEnabled: isValid
                        ) {
                            Task { await save() }
                        }
                        .padding(.top, 4)

                        // A tela mostra a quebra de tarifas: tem que dizer quem
                        // presta o serviço financeiro.
                        GwProviderFooter(provider: store.overview?.provider ?? .asaasPadrao)
                    }
                    .padding(Theme.screenPadding)
                }
            }
            .navigationTitle("Nova cobrança")
            .navigationBarTitleDisplayMode(.inline)
            // Taxas e situação da conta vêm do servidor. Se a chamada falhar, o
            // resumo do líquido simplesmente não aparece — melhor não mostrar
            // nada do que um número que pode estar errado.
            .task {
                await store.load(showSpinner: false)
            }
            .sheet(item: $pixCriado, onDismiss: {
                if fecharAoFecharPix { dismiss() }
            }) { pix in
                FinGatewayChargePixSheet(
                    charge: pix,
                    simulation: store.simulation,
                    provider: store.overview?.provider,
                    aviso: avisoDoEnvio
                ) {
                    onSaved()
                }
            }
            .navigationDestination(isPresented: $escolhendoPaciente) {
                FinPatientPickerView { escolhido in
                    paciente = escolhido
                    escolhendoPaciente = false
                }
                .navigationTitle("Paciente")
                .navigationBarTitleDisplayMode(.inline)
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

            // Só o Acolher Financeiro cobra. Sem conta aprovada o cartão
            // aparece apagado, com o motivo — e o link abaixo leva pra abrir.
            if podeCobrarPorPix, let cartao {
                opcoesDeRecebimento(cartao)
            } else {
            ThemeCard {
                HStack(spacing: 12) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 32, height: 32)
                        .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pix pelo Acolher Financeiro")
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(podeCobrarPorPix
                             ? (taxas.map { "Cai no seu saldo na hora · taxa \(Formatters.brl($0.totalPerCharge))" } ?? "Cai no seu saldo na hora")
                             : "Abra sua conta no Acolher Financeiro para cobrar")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .opacity(podeCobrarPorPix || store.overview == nil ? 1 : 0.45)
            }
            }

            if store.overview != nil, !podeCobrarPorPix {
                NavigationLink {
                    FinGatewayHomeView()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "building.columns")
                        Text("Abrir minha conta no Acolher Financeiro")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .padding(.leading, 2)
                    .padding(.top, 2)
                }
                .buttonStyle(.pressable)
            }
        }
    }

    /// Pix ou Cartão, lado a lado, e o repasse das taxas quando é cartão.
    private func opcoesDeRecebimento(_ cartao: GwCardFees) -> some View {
        VStack(spacing: 10) {
            opcao(
                icone: "qrcode",
                titulo: "Pix",
                subtitulo: taxas.map { "Cai no seu saldo na hora · taxa \(Formatters.brl($0.totalPerCharge))" } ?? "Cai no seu saldo na hora",
                selecionada: !noCartao
            ) { noCartao = false }
            opcao(
                icone: "creditcard",
                titulo: "Cartão de crédito",
                subtitulo: "À vista, pelo link seguro do \(store.overview?.provider.name ?? GwProvider.asaasPadrao.name). Você recebe em até 2 dias úteis.",
                selecionada: noCartao
            ) { noCartao = true }
            if noCartao {
                ThemeCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: Binding(
                            get: { repassar },
                            set: { repassarEscolhido = $0 }
                        )) {
                            Text("Repassar as taxas ao paciente")
                                .font(Theme.body(15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .tint(Theme.primary)
                        Text(repassar
                             ? "O paciente paga um pouco mais e você recebe o valor cheio."
                             : "O paciente paga o valor da cobrança e as taxas saem do que você recebe.")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: noCartao)
    }

    private func opcao(
        icone: String,
        titulo: String,
        subtitulo: String,
        selecionada: Bool,
        acao: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            acao()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icone)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 32, height: 32)
                    .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo)
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitulo)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: selecionada ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selecionada ? Theme.primary : Theme.border)
            }
            .padding(Theme.cardPadding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(selecionada ? Theme.primary : Theme.border, lineWidth: selecionada ? 1.5 : 1)
            )
        }
        .buttonStyle(.pressableSubtle)
        .accessibilityAddTraits(selecionada ? .isSelected : [])
    }

    // MARK: - Quanto entra na conta

    @ViewBuilder
    private var resumoDoLiquido: some View {
        if abaixoDoMinimo {
            ThemeCard {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warning)
                    Text("Cobrança por Pix a partir de \(Formatters.brl(minimo)).")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if usandoCartao, let cartao, let valor, valor > 0 {
            resumoDoCartao(cartao.estimativa(valor: valor, repassar: repassar))
                .transition(.opacity)
        } else if podeCobrarPorPix, let taxas, let valor, valor > 0 {
            // Taxa da plataforma e tarifa Pix do Asaas, sempre separadas
            // (regra do playbook) — e o líquido é o que ele recebe de fato.
            ThemeCard {
                VStack(spacing: 10) {
                    linha("Valor da cobrança", Formatters.brl(valor), destaque: false)
                    linha("Taxa de plataforma Terapia Acolher", "− \(Formatters.brl(taxas.platformFixed))", destaque: false)
                    linha("Tarifa Pix \(store.overview?.provider.name ?? GwProvider.asaasPadrao.name)", "− \(Formatters.brl(taxas.providerPixFixed))", destaque: false)
                    Divider().overlay(Theme.border)
                    linha("Você recebe", Formatters.brl(max(0, valor - taxas.totalPerCharge)), destaque: true)
                    HStack {
                        Spacer()
                        Text("no seu saldo do Acolher Financeiro na hora")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .transition(.opacity)
        }
    }

    /// Estimativa local: a cobrança ainda não existe para pedir a prévia ao
    /// servidor. O valor exato aparece na folha do link, ao gerar.
    private func resumoDoCartao(_ q: GwCardQuote) -> some View {
        let provedor = store.overview?.provider.name ?? GwProvider.asaasPadrao.name
        return ThemeCard {
            VStack(spacing: 10) {
                linha(q.passFees ? "O paciente paga" : "Valor da cobrança", Formatters.brl(q.chargedAmount), destaque: false)
                if q.fees.platform > 0 {
                    linha("Taxa Terapia Acolher", "− \(Formatters.brl(q.fees.platform))", destaque: false)
                }
                // Antecipação embutida na tarifa do Asaas (2026-10-06).
                linha("Tarifa do cartão \(provedor)", "− \(Formatters.brl(q.fees.provider + (q.fees.anticipation ?? 0)))", destaque: false)
                Divider().overlay(Theme.border)
                linha("Você recebe", Formatters.brl(q.netAmount), destaque: true)
                Text("Estimativa. O valor exato aparece ao gerar o link. No cartão, contestações do pagamento podem ser debitadas da sua conta.")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        let avulsa = !paraPaciente
        let body = FinChargeBody(
            patientId: avulsa ? nil : paciente?.id,
            payer: avulsa
                ? FinPayerBody(
                    name: nomePagador.trimmingCharacters(in: .whitespaces),
                    document: digitosDoDocumento,
                    email: emailPagador.trimmingCharacters(in: .whitespaces).isEmpty
                        ? nil : emailPagador.trimmingCharacters(in: .whitespaces)
                )
                : nil,
            description: descriptionText.trimmingCharacters(in: .whitespaces),
            amount: amount,
            dueDate: FinFormat.isoDay.string(from: dueDate),
            referenceMonth: FinFormat.monthQuery.string(from: referenceMonthDate),
            intendedBillingType: usandoCartao ? "CARD" : "PIX"
        )
        let cartaoAgora = usandoCartao
        let repassarAgora = repassar
        let enviarWhatsAppAgora = !avulsa && enviarAgora && motivoSemWhatsApp == nil
        let lembreteEm: Date? = !avulsa && agendarLembrete ? dataDoLembrete : nil
        do {
            let criada = try await FinanceAPI.createCharge(body)
            onSaved()
            // Gera o Pix na sequência. Criar a cobrança e não ter o que mandar
            // ao paciente deixava o terapeuta no meio do caminho: ele tinha que
            // achar a cobrança na lista e só então pedir o Pix.
            do {
                let gerada = cartaoAgora
                    ? try await FinGatewayAPI.createCard(chargeId: criada.id, passFees: repassarAgora)
                    : try await FinGatewayAPI.createPix(chargeId: criada.id)
                // Avisar o paciente DEPOIS do link existir: o lembrete leva o
                // botão de pagar. Falha aqui não desfaz a cobrança — vira aviso.
                avisoDoEnvio = await avisar(
                    chargeId: criada.id,
                    whatsAppAgora: enviarWhatsAppAgora,
                    lembreteEm: lembreteEm
                )
                pixCriado = gerada
                fecharAoFecharPix = true
                Haptics.success()
            } catch {
                // A cobrança FOI criada. Tratar como erro genérico faria ele
                // criar tudo de novo e ficar com duas.
                let oQue = cartaoAgora ? "o link do cartão" : "o Pix"
                errorMessage = (error as? APIError).map {
                    "Cobrança criada, mas \(oQue) não foi gerado: \($0.message)"
                } ?? "Cobrança criada, mas \(oQue) não foi gerado. Você pode gerar abrindo a cobrança."
            }
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível criar a cobrança."
        }
    }

    // MARK: - Enviar agora / agendar

    private func avisar(chargeId: String, whatsAppAgora: Bool, lembreteEm: Date?) async -> FinAvisoDeEnvio? {
        var partes: [String] = []
        var deuCerto = true
        if whatsAppAgora {
            do {
                let r = try await FinanceAPI.sendReminder(id: chargeId)
                if r.whatsappSent == false {
                    deuCerto = false
                    partes.append("O WhatsApp não foi enviado (mensagens desligadas ou cota do plano).")
                } else {
                    partes.append("Enviado pelo WhatsApp ✓")
                }
            } catch {
                deuCerto = false
                partes.append((error as? APIError)?.message ?? "Não foi possível enviar pelo WhatsApp.")
            }
        }
        if let lembreteEm {
            do {
                _ = try await FinanceAPI.scheduleReminder(id: chargeId, at: lembreteEm)
                partes.append("Lembrete agendado para \(FinFormat.diaEHora.string(from: lembreteEm)).")
            } catch {
                deuCerto = false
                partes.append((error as? APIError)?.message ?? "Não foi possível agendar o lembrete.")
            }
        }
        guard !partes.isEmpty else { return nil }
        return FinAvisoDeEnvio(texto: partes.joined(separator: " "), ok: deuCerto)
    }

    // MARK: - Para quem é a cobrança

    private var destinatario: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Para quem", selection: $paraPaciente.animation(.easeOut(duration: 0.2))) {
                Text("Paciente").tag(true)
                Text("Outra pessoa").tag(false)
            }
            .pickerStyle(.segmented)
            .onChange(of: paraPaciente) { _, _ in Haptics.tap() }

            if paraPaciente {
                Button {
                    Haptics.tap()
                    escolhendoPaciente = true
                } label: {
                    ThemeCard {
                        HStack(spacing: 12) {
                            if let paciente {
                                InitialAvatar(name: paciente.name, size: 40)
                                Text(paciente.name)
                                    .font(Theme.body(16, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                            } else {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Theme.primary)
                                Text("Escolher paciente")
                                    .font(Theme.body(15, weight: .semibold))
                                    .foregroundStyle(Theme.primary)
                            }
                            Spacer()
                            Text(paciente == nil ? "" : "Trocar")
                                .font(Theme.body(13, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary.opacity(0.6))
                        }
                    }
                }
                .buttonStyle(.pressableSubtle)
            } else {
                fieldCard("Nome") {
                    TextField("Nome de quem vai pagar", text: $nomePagador)
                        .font(Theme.body(15))
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                }
                fieldCard("CPF ou CNPJ") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("000.000.000-00", text: Binding(
                            get: { documentoPagador },
                            set: { novo in
                                let d = String(novo.filter(\.isNumber).prefix(14))
                                documentoPagador = d.count <= 11 ? GwMask.cpf(d) : GwMask.cnpj(d)
                            }
                        ))
                        .font(Theme.body(15))
                        .keyboardType(.numberPad)
                        if digitosDoDocumento.count >= 11, !documentoValido {
                            Text(digitosDoDocumento.count == 11 ? "CPF inválido." : "CNPJ inválido.")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.danger)
                        } else {
                            Text("O Asaas exige o documento de quem paga.")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                fieldCard("E-mail (opcional)") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("email@exemplo.com", text: $emailPagador)
                            .font(Theme.body(15))
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !emailPagadorValido {
                            Text("E-mail inválido.")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.danger)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Avisar o paciente

    private var avisarPaciente: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AVISAR O PACIENTE")
                .font(Theme.body(10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 2)
            ThemeCard {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $enviarAgora) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enviar agora pelo WhatsApp")
                                .font(Theme.body(15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(motivoSemWhatsApp ?? "Vai com o link de pagamento, pelo número oficial.")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Theme.primary)
                    .disabled(motivoSemWhatsApp != nil)
                    .onChange(of: enviarAgora) { _, _ in Haptics.tap() }

                    Divider().overlay(Theme.border)

                    Toggle(isOn: $agendarLembrete.animation(.easeOut(duration: 0.2))) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Agendar lembrete")
                                .font(Theme.body(15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Mandamos o lembrete com o link no horário escolhido.")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Theme.primary)
                    .onChange(of: agendarLembrete) { _, _ in Haptics.tap() }

                    if agendarLembrete {
                        DatePicker(
                            "Quando",
                            selection: Binding(
                                get: { dataDoLembrete },
                                set: { dataDoLembrete = $0; lembreteTocado = true }
                            ),
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .font(Theme.body(15, weight: .semibold))
                        .tint(Theme.primary)
                        .environment(\.locale, Locale(identifier: "pt_BR"))
                        if dataDoLembrete <= Date() {
                            Text("Escolha um horário no futuro.")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.danger)
                        }
                    }
                }
            }
        }
    }

}
