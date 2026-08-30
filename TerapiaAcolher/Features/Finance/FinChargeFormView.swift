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
    @State private var metodoId = "PIX"
    /// Cobrança combinada fora do app (dinheiro, transferência direta) não
    /// passa pelo gateway e não tem taxa — por isso a escolha é explícita.
    @State private var online = true

    /// Cobrança criada, com o link já gerado. Leva direto para o link em vez de
    /// só fechar a tela: criar e não ter o que mandar ao paciente deixava o
    /// terapeuta no meio do caminho.
    @State private var recemCriada: FinCheckoutResult?

    private var valor: Double? { FinFormat.parseAmount(amountText) }

    /// O que cai na conta do terapeuta. Uma taxa só, somada — ele não precisa
    /// saber que ela se divide entre gateway e plataforma.
    private var liquido: Double? {
        guard online, let valor, let fees else { return nil }
        return max(0, valor - fees.platformFee)
    }

    private var abaixoDoMinimo: Bool {
        guard online, let valor, let fees else { return false }
        return valor > 0 && valor < fees.minOnlineCharge
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
        if abaixoDoMinimo, let fees {
            ThemeCard {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warning)
                    Text("Cobrança online a partir de \(Formatters.brl(fees.minOnlineCharge)). Abaixo disso, combine por fora.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if let liquido, let valor, valor > 0, let fees {
            ThemeCard {
                VStack(spacing: 10) {
                    linha("Valor da cobrança", Formatters.brl(valor), destaque: false)
                    linha("Taxa do sistema", "− \(Formatters.brl(fees.platformFee))", destaque: false)
                    Divider().overlay(Theme.border)
                    linha("Você recebe", Formatters.brl(liquido), destaque: true)
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
            referenceMonth: FinFormat.monthQuery.string(from: referenceMonthDate)
        )
        do {
            _ = try await FinanceAPI.createCharge(body)
            onSaved()
            dismiss()
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível criar a cobrança."
        }
    }
}
