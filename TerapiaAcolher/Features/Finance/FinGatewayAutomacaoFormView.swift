import SwiftUI

/// Nova cobrança automática / editar (2026-10-23, igual ao web —
/// `gateway/automacoes/formulario.tsx`). Editar vale daqui pra frente: as
/// cobranças já criadas pela automação continuam como estão. Aberta pelo
/// calendário, vale da data tocada em diante (`aPartirDe`).
struct FinGatewayAutomacaoFormView: View {
    let automacao: Automacao?
    /// Editar pelo calendário: vale desta data em diante ("AAAA-MM-DD").
    let aPartirDe: String?
    /// Mensagem de sucesso para a tela de trás mostrar.
    var aoSalvar: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var store = FinGatewayStore.shared

    @State private var paciente: FinPatientRef?
    @State private var corDoPaciente: String?
    @State private var escolhendoPaciente = false
    /// Ficha do paciente: valor da sessão e contato (para o aviso de WhatsApp).
    @State private var ficha: PatientDetail?

    @State private var descricao: String
    /// nil = ainda não mexeu: mostra o valor da sessão da ficha do paciente.
    @State private var valorDigitado: String?
    @State private var forma: AutForma
    @State private var repassar: Bool?
    @State private var frequencia: AutFrequencia
    @State private var diaDaSemana: Int
    @State private var diaDoMes: Int
    /// Mensal: "todo dia X" ou "todo Nº dia útil".
    @State private var porDiaUtil: Bool
    @State private var diaUtil: Int
    @State private var hora: Date
    @State private var prazo: Int
    @State private var reenviar: Bool
    @State private var diasDoReenvio: Int

    @State private var salvando = false
    @State private var erro: String?

    init(automacao: Automacao?, aPartirDe: String? = nil, aoSalvar: @escaping (String) -> Void) {
        self.automacao = automacao
        self.aPartirDe = automacao != nil ? aPartirDe : nil
        self.aoSalvar = aoSalvar
        let a = automacao
        _paciente = State(initialValue: a.map { FinPatientRef(id: $0.patient.id, name: $0.patient.name) })
        _corDoPaciente = State(initialValue: a?.patient.group?.color)
        _descricao = State(initialValue: a?.description ?? "Psicoterapia")
        _valorDigitado = State(initialValue: a.map { GwFormat.amountText($0.amount) })
        _forma = State(initialValue: a?.billingType ?? .pix)
        _repassar = State(initialValue: a?.passFees)
        _frequencia = State(initialValue: a?.frequency ?? .semanal)
        _diaDaSemana = State(initialValue: a?.weekday ?? 1)
        _diaDoMes = State(initialValue: a?.monthDay ?? 5)
        _porDiaUtil = State(initialValue: a?.businessDay != nil)
        _diaUtil = State(initialValue: a?.businessDay ?? 5)
        _hora = State(initialValue: Self.data(daHora: a?.sendTime ?? "09:00"))
        _prazo = State(initialValue: a?.dueInDays ?? 0)
        _reenviar = State(initialValue: a?.retryEnabled ?? true)
        _diasDoReenvio = State(initialValue: a?.retryAfterDays ?? 3)
    }

    // MARK: Derivados

    private var editando: Bool { automacao != nil }
    /// "23/11" quando a edição veio do calendário.
    private var desde: String? { aPartirDe.map(AutTexto.ddmm) }

    private var comCartao: Bool {
        store.overview?.fees.cartaoDisponivel == true && store.isApproved
    }

    /// Repasse das taxas: começa com a preferência da conta.
    private var repassarAgora: Bool {
        repassar ?? store.account?.cardFeesPassThrough ?? false
    }

    private var valorDoCampo: String {
        if let valorDigitado { return valorDigitado }
        if let preco = ficha?.sessionPrice, preco > 0 { return GwFormat.amountText(preco) }
        return ""
    }

    private var valor: Double? { FinFormat.parseAmount(valorDoCampo) }
    private var minimo: Double { store.overview?.fees.minCharge ?? 5 }

    private var abaixoDoMinimo: Bool {
        guard let valor else { return false }
        return valor > 0 && valor < minimo
    }

    private var horaTexto: String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: hora)
        return String(format: "%02d:%02d", c.hour ?? 9, c.minute ?? 0)
    }

    private var regra: AutRegra {
        AutRegra(
            frequencia: frequencia,
            diaDaSemana: frequencia == .semanal ? diaDaSemana : nil,
            diaDoMes: frequencia == .mensal && !porDiaUtil ? diaDoMes : nil,
            diaUtil: frequencia == .mensal && porDiaUtil ? diaUtil : nil,
            hora: horaTexto
        )
    }

    private var valido: Bool {
        guard paciente != nil,
              !descricao.trimmingCharacters(in: .whitespaces).isEmpty,
              let valor, valor > 0, !abaixoDoMinimo
        else { return false }
        return true
    }

    /// Por que o WhatsApp não sai para este paciente (nil = sai).
    private var motivoSemWhatsapp: String? {
        guard let ficha else { return nil }
        if (ficha.whatsapp ?? "").filter(\.isNumber).isEmpty {
            return "Este paciente não tem WhatsApp cadastrado."
        }
        if ficha.whatsappEnabled == false || ficha.whatsappChargeReminder == false {
            return "As mensagens de cobrança estão desligadas para este paciente."
        }
        return nil
    }

    private var titulo: String {
        if let desde { return "Editar a partir de \(desde)" }
        return editando ? "Editar automação" : "Nova automação"
    }

    private var tituloDoBotao: String {
        if let desde { return "Salvar a partir de \(desde)" }
        return editando ? "Salvar daqui pra frente" : "Criar automação"
    }

    private var explicacao: String {
        if let desde {
            return "Vale de \(desde) em diante. As cobranças antes dessa data continuam como estão."
        }
        return editando
            ? "Vale daqui pra frente. As cobranças já criadas não mudam."
            : "O Acolher Financeiro cria a cobrança e manda ao paciente sozinho."
    }

    // MARK: Tela

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(explicacao)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 2)

                        blocoDoPaciente
                        blocoDaDescricao
                        blocoDoValor
                        blocoDaForma
                        blocoDoQuando
                        blocoDaHoraEVencimento
                        blocoDoReenvio

                        if let paciente, valido {
                            resumo(paciente)
                                .transition(.opacity)
                        }

                        PrimaryButton(title: tituloDoBotao, isLoading: salvando, isEnabled: valido) {
                            Task { await salvar() }
                        }
                        .padding(.top, 4)
                        .accessibilityIdentifier("autSalvar")

                        GwProviderFooter(provider: store.overview?.provider ?? .asaasPadrao)
                    }
                    .padding(Theme.screenPadding)
                    .animation(.easeOut(duration: 0.2), value: frequencia)
                    .animation(.easeOut(duration: 0.2), value: porDiaUtil)
                    .animation(.easeOut(duration: 0.2), value: forma)
                    .animation(.easeOut(duration: 0.2), value: reenviar)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                        .disabled(salvando)
                }
            }
            .navigationDestination(isPresented: $escolhendoPaciente) {
                FinPatientPickerView { escolhido in
                    paciente = escolhido
                    corDoPaciente = nil
                    ficha = nil
                    escolhendoPaciente = false
                }
                .navigationTitle("Quem você vai cobrar?")
                .navigationBarTitleDisplayMode(.inline)
            }
            .task { await store.load(showSpinner: false) }
            .task(id: paciente?.id) { await carregarFicha() }
            .alert("Ops", isPresented: .init(
                get: { erro != nil },
                set: { if !$0 { erro = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(erro ?? "")
            }
        }
        .interactiveDismissDisabled(salvando)
    }

    // MARK: Blocos

    private func rotulo(_ texto: String) -> some View {
        Text(texto.uppercased())
            .font(Theme.body(10, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.textSecondary)
            .padding(.leading, 2)
    }

    private var blocoDoPaciente: some View {
        VStack(alignment: .leading, spacing: 8) {
            rotulo("Paciente")
            if editando, let paciente {
                ThemeCard(padding: 12) {
                    linhaDoPaciente(paciente.name, acao: nil)
                }
            } else {
                Button {
                    escolhendoPaciente = true
                } label: {
                    ThemeCard(padding: 12) {
                        if let paciente {
                            linhaDoPaciente(paciente.name, acao: "Trocar")
                        } else {
                            HStack {
                                Text("Escolher paciente")
                                    .font(Theme.body(15))
                                    .foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                .buttonStyle(.pressableSubtle)
                .accessibilityIdentifier("autEscolherPaciente")
            }
            if let paciente, let motivo = motivoSemWhatsapp {
                let semContato = (ficha?.email ?? "").isEmpty
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .padding(.top, 2)
                    Text(semContato
                         ? "\(motivo) Sem e-mail também: a cobrança é criada, mas não chega a \(AutTexto.primeiroNome(paciente.name))."
                         : "\(motivo) A cobrança vai por e-mail.")
                        .font(Theme.body(12.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.warning)
                .padding(.horizontal, 2)
            }
        }
    }

    private func linhaDoPaciente(_ nome: String, acao: String?) -> some View {
        HStack(spacing: 12) {
            InitialAvatar(name: nome, colorHex: corDoPaciente ?? ficha?.group?.color, size: 36)
            Text(nome)
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let acao {
                Text(acao)
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.primary)
            }
        }
    }

    private var blocoDaDescricao: some View {
        VStack(alignment: .leading, spacing: 8) {
            rotulo("Descrição")
            ThemeCard {
                TextField("Ex.: Psicoterapia", text: $descricao)
                    .font(Theme.body(15))
                    .onChange(of: descricao) { _, novo in
                        if novo.count > 120 { descricao = String(novo.prefix(120)) }
                    }
            }
            Text(dicaDaDescricao)
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
    }

    /// Como a cobrança sai: "Psicoterapia · semana de 26/10" / "· outubro de 2026".
    /// O exemplo usa a próxima data da regra, como a descrição do backend.
    private var dicaDaDescricao: String {
        let base = descricao.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Psicoterapia" : descricao.trimmingCharacters(in: .whitespaces)
        let proxima = AutDia.proximaData(regra)
        if frequencia == .semanal {
            return "A cobrança sai como \"\(base) · semana de \(AutTexto.ddmm(proxima))\"."
        }
        let (ano, mes, _) = AutDia.partes(proxima)
        return "A cobrança sai como \"\(base) · \(AutDia.mesAno(ano, mes).lowercased())\"."
    }

    private var blocoDoValor: some View {
        VStack(alignment: .leading, spacing: 8) {
            rotulo("Valor")
            ThemeCard {
                CampoDinheiro(
                    texto: Binding(get: { valorDoCampo }, set: { valorDigitado = $0 }),
                    fonte: Theme.money(17)
                )
                .accessibilityIdentifier("autValor")
            }
            if abaixoDoMinimo {
                Text("Cobrança a partir de \(Formatters.brl(minimo)).")
                    .font(Theme.body(12, weight: .medium))
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 2)
            } else if valorDigitado == nil, ficha?.sessionPrice != nil {
                Text("Valor da sessão na ficha do paciente.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 2)
            }
        }
    }

    private var blocoDaForma: some View {
        VStack(alignment: .leading, spacing: 8) {
            rotulo("Como o paciente paga")
            opcaoDeForma(.pix, titulo: "Pix", detalhe: "Cai no seu saldo na hora", habilitada: true)
            opcaoDeForma(
                .cartao,
                titulo: "Cartão de crédito",
                detalhe: comCartao ? "À vista · até 2 dias úteis" : "Indisponível na sua conta",
                habilitada: comCartao
            )
            if forma == .cartao {
                ThemeCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: Binding(get: { repassarAgora }, set: { repassar = $0 })) {
                            Text("Repassar as taxas ao paciente")
                                .font(Theme.body(15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .tint(Theme.primary)
                        Text(repassarAgora
                             ? "O paciente paga um pouco mais e você recebe o valor cheio."
                             : "O paciente paga o valor da cobrança e as taxas saem do que você recebe.")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func opcaoDeForma(_ f: AutForma, titulo: String, detalhe: String, habilitada: Bool) -> some View {
        let ativa = forma == f
        return Button {
            forma = f
        } label: {
            HStack(spacing: 12) {
                Image(systemName: f.icone)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ativa ? .white : Theme.primary)
                    .frame(width: 32, height: 32)
                    .background(ativa ? Theme.primary : Theme.primarySoft, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo)
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(detalhe)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: ativa ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(ativa ? Theme.primary : Theme.border)
            }
            .padding(Theme.cardPadding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(ativa ? Theme.primary : Theme.border, lineWidth: ativa ? 1.5 : 1)
            )
            .opacity(habilitada ? 1 : 0.5)
        }
        .buttonStyle(.pressableSubtle)
        .disabled(!habilitada)
        .accessibilityAddTraits(ativa ? .isSelected : [])
    }

    private var blocoDoQuando: some View {
        VStack(alignment: .leading, spacing: 10) {
            rotulo("Quando cobrar")
            Picker("Frequência", selection: $frequencia) {
                Text("Toda semana").tag(AutFrequencia.semanal)
                Text("Todo mês").tag(AutFrequencia.mensal)
            }
            .pickerStyle(.segmented)

            if frequencia == .semanal {
                HStack(spacing: 6) {
                    ForEach(0 ..< 7, id: \.self) { i in
                        chipQuadrado(AutTexto.diasCurtos[i], ativo: diaDaSemana == i) { diaDaSemana = i }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    tipoDeDia(util: false, titulo: "Dia do mês", detalhe: "Ex.: todo dia 5")
                    tipoDeDia(util: true, titulo: "Dia útil", detalhe: "Ex.: 5º dia útil")
                }
                if porDiaUtil {
                    VStack(alignment: .leading, spacing: 8) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                            ForEach(1 ... 10, id: \.self) { n in
                                chipQuadrado("\(n)º", ativo: diaUtil == n) { diaUtil = n }
                                    .accessibilityLabel("\(n)º dia útil")
                            }
                        }
                        Text("Segunda a sexta, sem feriado nacional. Próximas: \(AutDiaUtil.proximas(diaUtil)).")
                            .font(Theme.body(12.5))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 2)
                    }
                    .transition(.opacity)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ThemeCard(padding: 12) {
                            HStack {
                                Text("Dia do mês")
                                    .font(Theme.body(15, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Picker("Dia do mês", selection: $diaDoMes) {
                                    ForEach(1 ... 28, id: \.self) { d in
                                        Text("Todo dia \(d)").tag(d)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(Theme.primary)
                            }
                        }
                        Text("Só até o dia 28, que existe em todos os meses.")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 2)
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private func chipQuadrado(_ texto: String, ativo: Bool, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Text(texto)
                .font(Theme.body(13, weight: ativo ? .semibold : .regular))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(ativo ? .white : Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(ativo ? Theme.primary : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(ativo ? Theme.primary : Theme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(ativo ? .isSelected : [])
    }

    private func tipoDeDia(util: Bool, titulo: String, detalhe: String) -> some View {
        let ativo = porDiaUtil == util
        return Button {
            porDiaUtil = util
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detalhe)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(ativo ? Theme.primarySoft : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(ativo ? Theme.primary : Theme.border, lineWidth: ativo ? 1.5 : 1)
            )
        }
        .buttonStyle(.pressableSubtle)
        .accessibilityAddTraits(ativo ? .isSelected : [])
        .accessibilityIdentifier(util ? "autDiaUtil" : "autDiaDoMes")
    }

    private var blocoDaHoraEVencimento: some View {
        ThemeCard(padding: 0) {
            VStack(spacing: 0) {
                DatePicker("Hora do envio", selection: $hora, displayedComponents: .hourAndMinute)
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.primary)
                    .environment(\.locale, Locale(identifier: "pt_BR"))
                    .padding(.horizontal, Theme.cardPadding)
                    .padding(.vertical, 10)
                Divider().overlay(Theme.border).padding(.leading, Theme.cardPadding)
                HStack {
                    Text("Vencimento")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Picker("Vencimento", selection: $prazo) {
                        ForEach(AutTexto.prazos, id: \.self) { p in
                            Text(p == 0 ? "No mesmo dia" : p == 1 ? "1 dia depois" : "\(p) dias depois").tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.primary)
                }
                .padding(.horizontal, Theme.cardPadding)
                .padding(.vertical, 8)
            }
        }
    }

    private var blocoDoReenvio: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $reenviar) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reenviar se vencer sem pagamento")
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Manda a cobrança de novo uma vez, se o paciente não pagar até o vencimento.")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Theme.primary)

                if reenviar {
                    FlowLayout(spacing: 8) {
                        ForEach([1, 2, 3], id: \.self) { d in
                            FilterChip(label: d == 1 ? "1 dia" : "\(d) dias", isSelected: diasDoReenvio == d) {
                                diasDoReenvio = d
                            }
                        }
                        Text("depois do vencimento")
                            .font(Theme.body(12.5))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(height: 36)
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    /// A frase que diz, em português, o que vai acontecer.
    private func resumo(_ paciente: FinPatientRef) -> some View {
        let valorTexto = Formatters.brl(valor ?? 0)
        let fim = reenviar
            ? "; se não pagar, \(AutTexto.reenvio(ligado: true, dias: diasDoReenvio))."
            : "; sem reenvio."
        let frase = Text(AutTexto.quandoSai(regra)).bold()
            + Text(", \(AutTexto.primeiroNome(paciente.name)) recebe a cobrança de ")
            + Text(valorTexto).bold()
            + Text(" por \(forma == .cartao ? "cartão" : "Pix"). A cobrança \(AutTexto.vencimento(prazo))\(fim)")
        return VStack(alignment: .leading, spacing: 6) {
            frase
                .font(Theme.body(13.5))
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("Quer pular uma data ou cobrar outro valor só uma vez? Faça isso no calendário.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.primarySoft.opacity(0.7), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.primary.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: Ações

    private func carregarFicha() async {
        guard let id = paciente?.id else { return }
        // A ficha só completa a tela (valor da sessão e aviso de contato):
        // se falhar, o formulário segue sem ela.
        if let detalhe = try? await PatientsAPI.detail(id: id), detalhe.id == paciente?.id {
            ficha = detalhe
            if corDoPaciente == nil { corDoPaciente = detalhe.group?.color }
        }
    }

    private func salvar() async {
        guard let paciente, let valor else { return }
        salvando = true
        defer { salvando = false }
        let r = regra
        let payload = AutPayload(
            patientId: editando ? nil : paciente.id,
            description: descricao.trimmingCharacters(in: .whitespaces),
            amount: (valor * 100).rounded() / 100,
            billingType: forma,
            passFees: forma == .cartao && repassarAgora,
            frequency: r.frequencia,
            weekday: r.diaDaSemana,
            monthDay: r.diaDoMes,
            businessDay: r.diaUtil,
            sendTime: r.hora,
            dueInDays: prazo,
            retryEnabled: reenviar,
            retryAfterDays: diasDoReenvio,
            fromDate: aPartirDe
        )
        do {
            if let automacao {
                _ = try await AutomacoesAPI.alterar(id: automacao.id, payload)
            } else {
                _ = try await AutomacoesAPI.criar(payload)
            }
            Haptics.success()
            let mensagem: String
            if let desde {
                mensagem = "Automação atualizada a partir de \(desde). As datas antes continuam como estavam."
            } else if editando {
                mensagem = "Automação atualizada. Vale daqui pra frente."
            } else {
                mensagem = "Cobrança automática criada."
            }
            aoSalvar(mensagem)
            dismiss()
        } catch is CancellationError {
            // fechou a folha no meio — silencioso
        } catch {
            Haptics.warning()
            erro = (error as? APIError)?.message ?? "Não foi possível salvar a automação."
        }
    }

    /// "09:30" → hoje às 09:30 (só hora e minuto importam).
    private static func data(daHora texto: String) -> Date {
        let p = texto.split(separator: ":").compactMap { Int($0) }
        let h = p.first ?? 9
        let m = p.count > 1 ? p[1] : 0
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
    }
}
