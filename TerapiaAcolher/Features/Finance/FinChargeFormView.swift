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

    /// Só o Gateway Acolher cobra: taxas e mínimo vêm de lá (do servidor —
    /// a taxa nunca é cravada no app).
    @State private var store = FinGatewayStore.shared
    /// Cobrança combinada fora do app (dinheiro, transferência direta) não
    /// passa pelo gateway e não tem taxa — por isso a escolha é explícita.
    @State private var online = true
    /// Pix do gateway gerado logo após criar. Criar e não ter o que mandar ao
    /// paciente deixava o terapeuta no meio do caminho.
    @State private var pixCriado: GwCharge?
    /// Fecha o sheet quando o Pix for fechado (a cobrança já existe).
    @State private var fecharAoFecharPix = false

    private var valor: Double? { FinFormat.parseAmount(amountText) }

    private var taxas: GwFees? { store.overview?.fees }
    private var podeCobrarPorPix: Bool { store.isApproved }

    private var minimo: Double { taxas?.minCharge ?? 5 }

    private var abaixoDoMinimo: Bool {
        guard online, podeCobrarPorPix, let valor else { return false }
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
            // Taxas e situação da conta vêm do servidor. Se a chamada falhar, o
            // resumo do líquido simplesmente não aparece — melhor não mostrar
            // nada do que um número que pode estar errado.
            .task {
                await store.load(showSpinner: false)
                if !podeCobrarPorPix { online = false }
            }
            .sheet(item: $pixCriado, onDismiss: {
                if fecharAoFecharPix { dismiss() }
            }) { pix in
                FinGatewayChargePixSheet(
                    charge: pix,
                    simulation: store.simulation,
                    provider: store.overview?.provider
                ) {
                    onSaved()
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
                    // Só o Gateway Acolher cobra. Sem conta aprovada a opção
                    // aparece, mas apagada, com o motivo — e leva pra abrir.
                    opcao(
                        titulo: "Pix pelo Gateway Acolher",
                        subtitulo: podeCobrarPorPix
                            ? (taxas.map { "Cai no seu saldo na hora · taxa \(Formatters.brl($0.totalPerCharge))" } ?? "Cai no seu saldo na hora")
                            : "Abra sua conta no Gateway Acolher para cobrar por Pix",
                        icone: "qrcode",
                        marcado: online && podeCobrarPorPix,
                        habilitado: podeCobrarPorPix
                    ) {
                        online = true
                    }
                    Divider().overlay(Theme.border)

                    // Recebimento por fora não passa pelo gateway: sem Pix,
                    // sem taxa. Existe porque muita sessão é paga em dinheiro
                    // ou por transferência direta, e a cobrança serve só de
                    // controle.
                    opcao(
                        titulo: "Combinar por fora",
                        subtitulo: "Dinheiro, transferência — sem taxa",
                        icone: "hand.raised",
                        marcado: !online || !podeCobrarPorPix,
                        habilitado: true
                    ) {
                        online = false
                    }
                }
            }

            if store.overview != nil, !podeCobrarPorPix {
                NavigationLink {
                    FinGatewayHomeView()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "building.columns")
                        Text("Abrir minha conta no Gateway Acolher")
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
                    Text("Cobrança por Pix a partir de \(Formatters.brl(minimo)). Abaixo disso, combine por fora.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if online, podeCobrarPorPix, let taxas, let valor, valor > 0 {
            // Taxa da plataforma e tarifa Pix do Asaas, sempre separadas
            // (regra do playbook) — e o líquido é o que ele recebe de fato.
            ThemeCard {
                VStack(spacing: 10) {
                    linha("Valor da cobrança", Formatters.brl(valor), destaque: false)
                    linha("Taxa de plataforma Terapia Acolher", "− \(Formatters.brl(taxas.platformFixed))", destaque: false)
                    linha("Tarifa Pix Asaas", "− \(Formatters.brl(taxas.providerPixFixed))", destaque: false)
                    Divider().overlay(Theme.border)
                    linha("Você recebe", Formatters.brl(max(0, valor - taxas.totalPerCharge)), destaque: true)
                    HStack {
                        Spacer()
                        Text("no seu saldo do gateway na hora")
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
        let porPix = online && podeCobrarPorPix
        let body = FinChargeBody(
            patientId: patient.id,
            description: descriptionText.trimmingCharacters(in: .whitespaces),
            amount: amount,
            dueDate: FinFormat.isoDay.string(from: dueDate),
            referenceMonth: FinFormat.monthQuery.string(from: referenceMonthDate),
            intendedBillingType: porPix ? "PIX" : nil
        )
        do {
            let criada = try await FinanceAPI.createCharge(body)
            onSaved()
            guard porPix else {
                dismiss()
                return
            }
            // Gera o Pix na sequência. Criar a cobrança e não ter o que mandar
            // ao paciente deixava o terapeuta no meio do caminho: ele tinha que
            // achar a cobrança na lista e só então pedir o Pix.
            do {
                pixCriado = try await FinGatewayAPI.createPix(chargeId: criada.id)
                fecharAoFecharPix = true
                Haptics.success()
            } catch {
                // A cobrança FOI criada. Tratar como erro genérico faria ele
                // criar tudo de novo e ficar com duas.
                errorMessage = (error as? APIError).map {
                    "Cobrança criada, mas o Pix não foi gerado: \($0.message)"
                } ?? "Cobrança criada, mas o Pix não foi gerado. Você pode gerá-lo abrindo a cobrança."
            }
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível criar a cobrança."
        }
    }
}
