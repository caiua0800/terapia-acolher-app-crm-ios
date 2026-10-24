import SwiftUI

// MARK: - Cobranças automáticas (Acolher Financeiro → Automações)
//
// 2026-10-23, igual ao web (`gateway/automacoes/automacoes.tsx`): o
// calendário das cobranças que vão sair (e das que já saíram), o dia tocado
// com o que dá para fazer só com ele, e a lista "Suas automações" com busca e
// filtros. Nos apps não há interruptor: aparece sempre que a conta está
// aprovada.

/// O formulário aberto: nova (`automacao == nil`), editar daqui pra frente
/// (pela lista) ou editar a partir de uma data (pelo calendário).
private struct FormularioAberto: Identifiable {
    let id = UUID()
    let automacao: Automacao?
    var desde: String?
}

/// `navigationDestination(item:)` pede Hashable; a cobrança não é.
private struct CobrancaAberta: Hashable {
    let charge: FinCharge
    static func == (a: Self, b: Self) -> Bool { a.charge.id == b.charge.id }
    func hash(into h: inout Hasher) { h.combine(charge.id) }
}

private enum FiltroDeSituacao: String, CaseIterable {
    case todas, ativas, pausadas, encerradas

    var rotulo: String {
        switch self {
        case .todas: "Todas"
        case .ativas: "Ativas"
        case .pausadas: "Pausadas"
        case .encerradas: "Encerradas"
        }
    }
}

private enum OrdemDaLista: String, CaseIterable {
    case proxima, paciente, valor, recentes

    var rotulo: String {
        switch self {
        case .proxima: "Próxima cobrança"
        case .paciente: "Paciente (A–Z)"
        case .valor: "Maior valor"
        case .recentes: "Criadas por último"
        }
    }
}

struct FinGatewayAutomacoesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = FinGatewayStore.shared

    // Lista
    @State private var automacoes: [Automacao] = []
    @State private var listaCarregada = false
    @State private var carregandoLista = false
    @State private var erroDaLista: String?

    // Calendário
    @State private var ano: Int
    @State private var mes: Int
    @State private var selecionado: String
    @State private var datas: [AutDataDaAutomacao] = []
    @State private var carregandoCalendario = true
    @State private var erroDoCalendario: String?

    // Ações
    @State private var formulario: FormularioAberto?
    @State private var cobrancaAberta: CobrancaAberta?
    @State private var toast: AgendaToastData?
    @State private var erro: String?
    /// "<id da data>-<ação>" em voo: o spinner acende só no botão tocado.
    @State private var acaoDaDataEmVoo: String?
    /// Data com o campo "Outro valor só nesta" aberto.
    @State private var mudandoValorDe: String?
    @State private var valorDaData = ""
    /// "<id>-pausar" / "<id>-retomar" / "<id>-excluir" em voo.
    @State private var acaoDaListaEmVoo: String?
    @State private var excluindo: Automacao?

    // Filtros da lista
    @State private var busca = ""
    @State private var situacao: FiltroDeSituacao = .todas
    @State private var frequencia: AutFrequencia?
    @State private var forma: AutForma?
    @State private var ordem: OrdemDaLista = .proxima
    @State private var visiveis = 20
    /// Com o teclado da busca aberto, o botão flutuante sai da frente.
    @FocusState private var buscando: Bool

    private static let porPagina = 20

    init() {
        let hoje = AutDia.hoje()
        let (a, m, _) = AutDia.partes(hoje)
        _ano = State(initialValue: a)
        _mes = State(initialValue: m)
        _selecionado = State(initialValue: hoje)
    }

    private var hoje: String { AutDia.hoje() }

    private var porDia: [String: [AutDataDaAutomacao]] {
        Dictionary(grouping: datas, by: \.date)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("O Acolher Financeiro cobra seus pacientes sozinho, no dia e na hora que você escolher.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if store.overview == nil && store.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    } else if store.overview != nil && !store.isApproved {
                        semConta
                    } else {
                        // Botão na largura toda, no topo (como no Android): flutuando,
                        // ele cobria a busca da lista ao rolar.
                        if store.isApproved { botaoNova }
                        calendario
                        painelDoDia
                        suasAutomacoes
                    }

                    GwProviderFooter(provider: store.overview?.provider ?? .asaasPadrao)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .refreshable { await recarregarTudo() }
            .scrollDismissesKeyboard(.interactively)

        }
        .setToolbarTitle("Cobranças automáticas")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.load(showSpinner: true)
            await carregarLista()
        }
        .task(id: "\(ano)-\(mes)") { await carregarCalendario() }
        .sheet(item: $formulario) { f in
            FinGatewayAutomacaoFormView(automacao: f.automacao, aPartirDe: f.desde) { mensagem in
                toast = AgendaToastData(message: mensagem, showUndo: false)
                Task { await recarregarTudo() }
            }
        }
        .navigationDestination(item: $cobrancaAberta) { aberta in
            FinChargeDetailView(charge: aberta.charge) {
                Task { await carregarCalendario() }
            }
        }
        .alert(
            "Excluir esta automação?",
            isPresented: .init(get: { excluindo != nil }, set: { if !$0 { excluindo = nil } }),
            presenting: excluindo
        ) { a in
            Button("Excluir", role: .destructive) {
                Task { await acaoNaLista(a, "excluir") }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { a in
            Text("As próximas cobranças de \(AutTexto.primeiroNome(a.patient.name)) deixam de sair. As que já foram criadas continuam em Cobranças.")
        }
        .alert("Ops", isPresented: .init(get: { erro != nil }, set: { if !$0 { erro = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(erro ?? "")
        }
        .agendaToast($toast)
    }

    // MARK: Sem conta aprovada

    private var semConta: some View {
        ThemeCard {
            VStack(spacing: 12) {
                Image(systemName: "repeat")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 48, height: 48)
                    .background(Theme.primarySoft, in: Circle())
                Text("Abra sua conta primeiro")
                    .font(Theme.serifTitle(20))
                    .foregroundStyle(Theme.textPrimary)
                Text("A cobrança automática usa o Pix e o cartão do Acolher Financeiro. Com a conta aprovada, é só criar a automação.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    dismiss()
                } label: {
                    Text("Ir para o Acolher Financeiro")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Theme.primary, in: Capsule())
                }
                .buttonStyle(.pressable)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    private var botaoNova: some View {
        Button {
            Haptics.tap()
            formulario = FormularioAberto(automacao: nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                Text("Nova automação")
                    .font(Theme.body(16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Theme.primary, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.95))
        .accessibilityIdentifier("autNova")
    }

    // MARK: Calendário

    private var calendario: some View {
        VStack(spacing: 12) {
            HStack {
                botaoDeMes("chevron.left", rotulo: "Mês anterior", delta: -1)
                Spacer()
                Text(AutDia.mesAno(ano, mes))
                    .font(Theme.serifTitle(20).italic())
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                botaoDeMes("chevron.right", rotulo: "Próximo mês", delta: 1)
            }

            if let erroDoCalendario {
                ThemeCard {
                    VStack(spacing: 10) {
                        Text(erroDoCalendario)
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                        RetryButton(isLoading: carregandoCalendario) {
                            Task { await carregarCalendario() }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ThemeCard(padding: 10) {
                    VStack(spacing: 6) {
                        HStack(spacing: 0) {
                            ForEach(AutTexto.diasCurtos, id: \.self) { d in
                                Text(d)
                                    .font(Theme.body(11, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 6)
                        .background(Color(hex: 0xF3EEE6), in: RoundedRectangle(cornerRadius: 8))

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                            ForEach(Array(celulas.enumerated()), id: \.offset) { _, dia in
                                if let dia {
                                    celula(dia)
                                } else {
                                    Color.clear.frame(height: 54)
                                }
                            }
                        }

                        legenda
                    }
                }
            }
        }
    }

    private var celulas: [Int?] {
        let primeiro = AutDia.diaDaSemana(ano, mes, 1)
        return Array(repeating: nil, count: primeiro) + (1 ... AutDia.diasNoMes(ano, mes)).map { Optional($0) }
    }

    private func celula(_ dia: Int) -> some View {
        let chave = AutDia.iso(ano, mes, dia)
        let itens = porDia[chave] ?? []
        let ativo = selecionado == chave
        let ehHoje = chave == hoje
        return Button {
            selecionado = chave
            mudandoValorDe = nil
        } label: {
            VStack(spacing: 4) {
                Text("\(dia)")
                    .font(Theme.body(13, weight: ehHoje || ativo ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(ehHoje ? .white : Theme.textPrimary)
                    .frame(width: 26, height: 26)
                    .background(ehHoje ? Theme.primary : .clear, in: Circle())
                if carregandoCalendario && datas.isEmpty {
                    Capsule().fill(Theme.border).frame(width: 18, height: 5)
                } else {
                    HStack(spacing: 3) {
                        ForEach(itens.prefix(3)) { item in
                            Circle()
                                .fill(item.aparencia.cor.opacity(item.riscada ? 0.45 : 1))
                                .frame(width: 6, height: 6)
                        }
                        if itens.count > 3 {
                            Text("+\(itens.count - 3)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(height: 8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(ativo ? Theme.primarySoft : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(dia): \(itens.count == 1 ? "1 cobrança" : "\(itens.count) cobranças")")
        .accessibilityAddTraits(ativo ? .isSelected : [])
    }

    private var legenda: some View {
        let itens: [(Color, String)] = [
            (Theme.online, "Agendada"),
            (Theme.warning, "Enviada"),
            (Theme.success, "Paga"),
            (Theme.danger, "Atrasada ou não saiu"),
            (Theme.textSecondary.opacity(0.5), "Cancelada ou pausada"),
        ]
        return VStack(spacing: 8) {
            Divider().overlay(Theme.border)
            FlowLayout(spacing: 12) {
                ForEach(itens, id: \.1) { cor, rotulo in
                    HStack(spacing: 5) {
                        Circle().fill(cor).frame(width: 7, height: 7)
                        Text(rotulo)
                            .font(Theme.body(11.5))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .padding(.top, 2)
    }

    private func botaoDeMes(_ icone: String, rotulo: String, delta: Int) -> some View {
        Button {
            trocarMes(delta)
        } label: {
            Image(systemName: icone)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 36, height: 36)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(rotulo)
    }

    private func trocarMes(_ delta: Int) {
        var m = mes + delta
        var a = ano
        if m < 1 { m = 12; a -= 1 }
        if m > 12 { m = 1; a += 1 }
        ano = a
        mes = m
        datas = []
        mudandoValorDe = nil
        // Mês de hoje: volta pra hoje; outro mês: o dia 1.
        let prefixo = String(AutDia.iso(a, m, 1).prefix(7))
        selecionado = hoje.hasPrefix(prefixo) ? hoje : AutDia.iso(a, m, 1)
    }

    // MARK: Dia escolhido

    private var painelDoDia: some View {
        let itens = porDia[selecionado] ?? []
        let total = itens.filter { $0.state != .cancelada }.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(AutDia.titulo(selecionado))
                        .font(Theme.serifTitle(19))
                        .foregroundStyle(Theme.textPrimary)
                    if selecionado == hoje {
                        Text("· hoje")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                if !itens.isEmpty {
                    Text("\(itens.count == 1 ? "1 cobrança" : "\(itens.count) cobranças") · \(Formatters.brl(total))")
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 2)

            if carregandoCalendario && datas.isEmpty {
                ThemeCard {
                    HStack(spacing: 12) {
                        Circle().fill(Theme.border).frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule().fill(Theme.border).frame(width: 140, height: 10)
                            Capsule().fill(Theme.border).frame(width: 90, height: 8)
                        }
                        Spacer()
                    }
                }
            } else if itens.isEmpty {
                ThemeCard {
                    Text("Nenhuma cobrança automática neste dia.\nEscolha outro dia no calendário.")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
            } else {
                ForEach(itens) { item in
                    cobrancaDoDia(item)
                }
            }
        }
    }

    private func cobrancaDoDia(_ item: AutDataDaAutomacao) -> some View {
        let ap = item.aparencia
        let nome = AutTexto.primeiroNome(item.patient.name)
        let automacao = automacoes.first { $0.id == item.automationId }
        let emVoo = acaoDaDataEmVoo?.hasPrefix(item.id) == true
        return ThemeCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    InitialAvatar(name: item.patient.name, colorHex: item.patient.group?.color, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(item.patient.name)
                                .font(Theme.body(15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            StatusBadge(label: ap.rotulo, color: ap.cor, background: ap.fundo)
                        }
                        FlowLayout(spacing: 5) {
                            Text(Formatters.brl(item.amount))
                                .font(Theme.money(13.5, weight: .semibold))
                                .strikethrough(item.state == .cancelada)
                                .foregroundStyle(item.state == .cancelada ? Theme.textSecondary : Theme.textPrimary)
                            if item.customAmount {
                                Text("valor só desta data")
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.primary)
                            }
                            Text("·").foregroundStyle(Theme.textSecondary)
                            Text(item.billingType.rotulo)
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textPrimary)
                            Text("·").foregroundStyle(Theme.textSecondary)
                            Text(AutDia.hora(deInstante: item.at))
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .font(Theme.body(13))
                        if let charge = item.charge {
                            Text(charge.status == "PAID" && charge.paidAt != nil
                                 ? "Paga em \(AutDia.diaCompleto(deInstante: charge.paidAt ?? ""))"
                                 : "Vencimento \(AutTexto.ddmm(charge.dueDate))")
                                .font(Theme.body(12.5))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        if item.state == .falhou, let motivo = item.failureReason {
                            Text(motivo).font(Theme.body(12.5)).foregroundStyle(Theme.danger)
                        }
                        if item.state == .naoEnviada {
                            Text("Esta data passou sem a cobrança sair.")
                                .font(Theme.body(12.5)).foregroundStyle(Theme.danger)
                        }
                        if item.state == .pausada {
                            Text("A automação está pausada: esta não sai.")
                                .font(Theme.body(12.5)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }

                if mudandoValorDe == item.id {
                    HStack(alignment: .bottom, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Valor só de \(AutTexto.ddmm(item.date))".uppercased())
                                .font(Theme.body(10, weight: .semibold))
                                .tracking(1)
                                .foregroundStyle(Theme.textSecondary)
                            CampoDinheiro(texto: $valorDaData, fonte: Theme.money(16))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                                .accessibilityIdentifier("autValorDaData")
                        }
                        let novo = FinFormat.parseAmount(valorDaData)
                        botaoPequeno(
                            "Salvar",
                            cheio: true,
                            carregando: acaoDaDataEmVoo == "\(item.id)-valor",
                            habilitado: (novo ?? 0) > 0 && !emVoo
                        ) {
                            guard let novo else { return }
                            Task {
                                await alterarData(item, chave: "valor", mensagem: "Em \(AutTexto.ddmm(item.date)), \(nome) recebe \(Formatters.brl(novo)).") {
                                    try await AutomacoesAPI.valorDaData(id: item.automationId, dia: item.date, valor: novo)
                                }
                            }
                        }
                    }
                    .padding(.leading, 52)
                    .transition(.opacity)
                }

                FlowLayout(spacing: 6) {
                    if let charge = item.charge {
                        botaoPequeno("Ver cobrança", carregando: acaoDaDataEmVoo == "\(item.id)-ver", habilitado: !emVoo) {
                            Task { await abrirCobranca(item, chargeId: charge.id) }
                        }
                    } else if item.editable && item.state == .cancelada {
                        botaoPequeno("Voltar a cobrar nesta data", carregando: acaoDaDataEmVoo == "\(item.id)-voltar", habilitado: !emVoo) {
                            Task {
                                await alterarData(item, chave: "voltar", mensagem: "A cobrança de \(AutTexto.ddmm(item.date)) volta a sair.") {
                                    try await AutomacoesAPI.cancelarData(id: item.automationId, dia: item.date, cancelada: false)
                                }
                            }
                        }
                    } else if item.editable && item.state == .agendada {
                        botaoPequeno("Não cobrar nesta data", carregando: acaoDaDataEmVoo == "\(item.id)-cancelar", habilitado: !emVoo) {
                            Task {
                                await alterarData(item, chave: "cancelar", mensagem: "A cobrança de \(nome) em \(AutTexto.ddmm(item.date)) não vai sair.") {
                                    try await AutomacoesAPI.cancelarData(id: item.automationId, dia: item.date, cancelada: true)
                                }
                            }
                        }
                        if mudandoValorDe != item.id {
                            botaoPequeno("Outro valor só nesta", habilitado: !emVoo) {
                                valorDaData = GwFormat.amountText(item.amount)
                                mudandoValorDe = item.id
                            }
                            .accessibilityIdentifier("autOutroValor")
                        }
                        if item.customAmount && mudandoValorDe != item.id {
                            botaoDeTexto("Voltar ao valor normal", carregando: acaoDaDataEmVoo == "\(item.id)-normal") {
                                Task {
                                    await alterarData(item, chave: "normal", mensagem: "Valor da automação de volta nesta data.") {
                                        try await AutomacoesAPI.valorDaData(id: item.automationId, dia: item.date, valor: nil)
                                    }
                                }
                            }
                        }
                    }
                    if let automacao {
                        botaoDeTexto("Editar desta data em diante", icone: "pencil") {
                            formulario = FormularioAberto(automacao: automacao, desde: item.date)
                        }
                        .accessibilityIdentifier("autEditarDesta")
                    }
                }
                .padding(.leading, 52)
            }
        }
        .animation(.easeOut(duration: 0.2), value: mudandoValorDe)
    }

    /// Botão de ação pequeno, em pílula, com o spinner no próprio botão.
    private func botaoPequeno(
        _ titulo: String,
        icone: String? = nil,
        cheio: Bool = false,
        tint: Color = Theme.textPrimary,
        carregando: Bool = false,
        habilitado: Bool = true,
        acao: @escaping () -> Void
    ) -> some View {
        Button(action: acao) {
            HStack(spacing: 6) {
                if carregando {
                    ProgressView().controlSize(.mini).tint(cheio ? .white : tint)
                } else if let icone {
                    Image(systemName: icone).font(.system(size: 11, weight: .semibold))
                }
                Text(titulo).font(Theme.body(12.5, weight: .semibold))
            }
            .foregroundStyle(cheio ? .white : tint)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(cheio ? Theme.primary : Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(cheio ? Theme.primary : Theme.border, lineWidth: 1))
            .opacity(habilitado || carregando ? 1 : 0.5)
            .animation(.easeInOut(duration: 0.15), value: carregando)
        }
        .buttonStyle(.pressable)
        .disabled(!habilitado || carregando)
    }

    private func botaoDeTexto(
        _ titulo: String,
        icone: String? = nil,
        carregando: Bool = false,
        acao: @escaping () -> Void
    ) -> some View {
        Button(action: acao) {
            HStack(spacing: 5) {
                if carregando {
                    ProgressView().controlSize(.mini).tint(Theme.primary)
                } else if let icone {
                    Image(systemName: icone).font(.system(size: 11, weight: .semibold))
                }
                Text(titulo).font(Theme.body(12.5, weight: .semibold))
            }
            .foregroundStyle(Theme.primary)
            .padding(.horizontal, 6)
            .frame(height: 32)
        }
        .buttonStyle(.pressable)
        .disabled(carregando)
    }

    // MARK: Suas automações

    private func situacaoDe(_ a: Automacao) -> FiltroDeSituacao {
        a.ended ? .encerradas : a.pausada ? .pausadas : .ativas
    }

    /// Tudo menos a situação: é sobre isso que os chips contam.
    private var semSituacao: [Automacao] {
        let termo = AutTexto.semAcento(busca.trimmingCharacters(in: .whitespaces))
        return automacoes.filter { a in
            (termo.isEmpty
                || AutTexto.semAcento(a.patient.name).contains(termo)
                || AutTexto.semAcento(a.description).contains(termo))
                && (frequencia == nil || a.frequency == frequencia)
                && (forma == nil || a.billingType == forma)
        }
    }

    private var filtradas: [Automacao] {
        let lista = semSituacao.filter { situacao == .todas || situacaoDe($0) == situacao }
        return lista.sorted { x, y in
            switch ordem {
            case .paciente:
                return x.patient.name.compare(y.patient.name, locale: Locale(identifier: "pt_BR")) == .orderedAscending
            case .valor:
                return x.amount > y.amount
            case .recentes:
                return x.createdAt > y.createdAt
            case .proxima:
                return (x.nextAt ?? "9999") < (y.nextAt ?? "9999")
            }
        }
    }

    private var temFiltro: Bool {
        !busca.trimmingCharacters(in: .whitespaces).isEmpty || situacao != .todas || frequencia != nil || forma != nil
    }

    private func limparFiltros() {
        busca = ""
        situacao = .todas
        frequencia = nil
        forma = nil
        visiveis = Self.porPagina
    }

    private var suasAutomacoes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SUAS AUTOMAÇÕES")
                .font(Theme.body(10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 2)
                .padding(.top, 6)

            if !listaCarregada && carregandoLista {
                ThemeCard {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                }
            } else if let erroDaLista, automacoes.isEmpty {
                ThemeCard {
                    VStack(spacing: 10) {
                        Text(erroDaLista)
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                        RetryButton(isLoading: carregandoLista) {
                            Task { await carregarLista() }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else if automacoes.isEmpty {
                ThemeCard(padding: 0) {
                    EmptyStateView(
                        icon: "repeat",
                        title: "Nenhuma automação ainda",
                        message: "Escolha o paciente, o valor e quando cobrar. Toda semana ou todo mês, a cobrança chega ao paciente sem você precisar criar.",
                        actionTitle: "Criar a primeira"
                    ) {
                        formulario = FormularioAberto(automacao: nil)
                    }
                }
            } else {
                filtros
                let lista = filtradas
                if lista.isEmpty {
                    ThemeCard(padding: 0) {
                        VStack(spacing: 10) {
                            Text("Nenhuma automação com esses filtros")
                                .font(Theme.serifTitle(18))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Tente outro nome ou tire algum filtro.")
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.textSecondary)
                            SecondaryButton(title: "Limpar filtros") { limparFiltros() }
                                .frame(maxWidth: 200)
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .padding(.horizontal, 20)
                    }
                } else {
                    ThemeCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(lista.prefix(visiveis).enumerated()), id: \.element.id) { indice, a in
                                if indice > 0 { Divider().overlay(Theme.border) }
                                linha(a)
                            }
                        }
                    }
                    if lista.count > visiveis {
                        SecondaryButton(title: "Carregar mais (\(lista.count - visiveis) restantes)") {
                            visiveis += Self.porPagina
                        }
                    }
                }
            }
        }
    }

    private var filtros: some View {
        let contagem: [FiltroDeSituacao: Int] = {
            let base = semSituacao
            return [
                .todas: base.count,
                .ativas: base.filter { situacaoDe($0) == .ativas }.count,
                .pausadas: base.filter { situacaoDe($0) == .pausadas }.count,
                .encerradas: base.filter { situacaoDe($0) == .encerradas }.count,
            ]
        }()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.textSecondary)
                TextField("Buscar por paciente ou descrição…", text: $busca)
                    .font(Theme.body(15))
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($buscando)
                    .onChange(of: busca) { _, _ in visiveis = Self.porPagina }
                if !busca.isEmpty {
                    Button { busca = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary.opacity(0.6))
                    }
                    .accessibilityLabel("Limpar busca")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FiltroDeSituacao.allCases, id: \.self) { f in
                        chipComContagem(f.rotulo, contagem[f] ?? 0, ativo: situacao == f) {
                            situacao = f
                            visiveis = Self.porPagina
                        }
                    }
                }
                .padding(.vertical, 1)
            }

            FlowLayout(spacing: 8) {
                menuDeFiltro(
                    frequencia == nil ? "Semanal e mensal" : frequencia == .semanal ? "Toda semana" : "Todo mês",
                    ativo: frequencia != nil
                ) {
                    Picker("Frequência", selection: $frequencia) {
                        Text("Semanal e mensal").tag(AutFrequencia?.none)
                        Text("Toda semana").tag(AutFrequencia?.some(.semanal))
                        Text("Todo mês").tag(AutFrequencia?.some(.mensal))
                    }
                }
                menuDeFiltro(forma?.rotulo ?? "Pix e cartão", ativo: forma != nil) {
                    Picker("Forma", selection: $forma) {
                        Text("Pix e cartão").tag(AutForma?.none)
                        Text("Pix").tag(AutForma?.some(.pix))
                        Text("Cartão").tag(AutForma?.some(.cartao))
                    }
                }
                menuDeFiltro(ordem.rotulo, icone: "arrow.up.arrow.down", ativo: false) {
                    Picker("Ordenar", selection: $ordem) {
                        ForEach(OrdemDaLista.allCases, id: \.self) { o in
                            Text(o.rotulo).tag(o)
                        }
                    }
                }
                if temFiltro {
                    Button("Limpar filtros") { limparFiltros() }
                        .font(Theme.body(12.5, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(height: 34)
                }
            }
        }
        .onChange(of: frequencia) { _, _ in visiveis = Self.porPagina }
        .onChange(of: forma) { _, _ in visiveis = Self.porPagina }
    }

    private func chipComContagem(_ rotulo: String, _ n: Int, ativo: Bool, acao: @escaping () -> Void) -> some View {
        Button {
            acao()
        } label: {
            HStack(spacing: 6) {
                Text(rotulo).font(Theme.body(14, weight: ativo ? .semibold : .regular))
                Text("\(n)")
                    .font(Theme.body(12, weight: .semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(ativo ? Color.white.opacity(0.18) : Theme.background, in: Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(ativo ? Theme.ink : Theme.surface)
            .foregroundStyle(ativo ? Color.white : Theme.textPrimary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: ativo ? 0 : 1))
            .animation(.easeOut(duration: 0.18), value: ativo)
        }
        .buttonStyle(.pressable)
    }

    private func menuDeFiltro<Conteudo: View>(
        _ rotulo: String,
        icone: String = "chevron.down",
        ativo: Bool,
        @ViewBuilder conteudo: () -> Conteudo
    ) -> some View {
        Menu {
            conteudo()
        } label: {
            HStack(spacing: 6) {
                Text(rotulo)
                    .font(Theme.body(13, weight: .medium))
                    .lineLimit(1)
                Image(systemName: icone)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(ativo ? Theme.primary : Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(ativo ? Theme.primarySoft : Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(ativo ? Theme.primary.opacity(0.4) : Theme.border, lineWidth: 1))
        }
    }

    private func selo(_ a: Automacao) -> StatusBadge {
        if a.ended { return StatusBadge(label: "ENCERRADA", color: Theme.textSecondary, background: Theme.border.opacity(0.7)) }
        if a.pausada { return StatusBadge(label: "PAUSADA", color: Theme.warning, background: Theme.warningSoft) }
        return StatusBadge(label: "ATIVA", color: Theme.success, background: Theme.successSoft)
    }

    private func linha(_ a: Automacao) -> some View {
        let apagada = a.pausada || a.ended
        let periodo = AutTexto.periodo(a)
        let emVoo = acaoDaListaEmVoo?.hasPrefix(a.id) == true
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                InitialAvatar(name: a.patient.name, colorHex: a.patient.group?.color, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.patient.name)
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(apagada ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(1)
                    Text(a.description)
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Formatters.brl(a.amount))
                        .font(Theme.money(14.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    selo(a)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                (Text(AutTexto.quandoSai(a.regra)).foregroundColor(Theme.textPrimary)
                    + Text(" · \(a.billingType.rotulo)").foregroundColor(Theme.textSecondary))
                    .font(Theme.body(13))
                Text("\(AutTexto.maiuscula(AutTexto.vencimento(a.dueInDays))) · \(AutTexto.reenvio(ligado: a.retryEnabled, dias: a.retryAfterDays))")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !periodo.isEmpty {
                    Text(periodo)
                        .font(Theme.body(12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
                if !apagada {
                    if let proxima = a.nextDate {
                        Text("Próxima: \(AutDia.semanaCurta(proxima)), \(AutTexto.ddmm(proxima)) · \(a.sendTime)")
                            .font(Theme.body(12.5, weight: .medium))
                            .foregroundStyle(Theme.primary)
                    } else {
                        Text("Sem próxima data")
                            .font(Theme.body(12.5))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                if a.pausada, let motivo = a.pausedReason {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .padding(.top, 1)
                        Text("Pausou sozinha: \(motivo)")
                            .font(Theme.body(12))
                            .lineLimit(2)
                    }
                    .foregroundStyle(Theme.warning)
                }
            }
            .padding(.leading, 48)

            HStack(spacing: 6) {
                botaoPequeno("Editar", icone: "pencil", habilitado: !emVoo) {
                    formulario = FormularioAberto(automacao: a)
                }
                .accessibilityIdentifier("autEditar-\(a.id)")
                botaoPequeno(
                    a.pausada ? "Retomar" : "Pausar",
                    icone: a.pausada ? "play.fill" : "pause.fill",
                    carregando: acaoDaListaEmVoo == "\(a.id)-\(a.pausada ? "retomar" : "pausar")",
                    habilitado: !emVoo
                ) {
                    Task { await acaoNaLista(a, a.pausada ? "retomar" : "pausar") }
                }
                botaoPequeno(
                    "Excluir",
                    icone: "trash",
                    tint: Theme.danger,
                    carregando: acaoDaListaEmVoo == "\(a.id)-excluir",
                    habilitado: !emVoo
                ) {
                    excluindo = a
                }
            }
            .padding(.leading, 48)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    // MARK: Carga e ações

    private func recarregarTudo() async {
        async let lista: Void = carregarLista()
        async let cal: Void = carregarCalendario()
        _ = await (lista, cal)
    }

    private func carregarLista() async {
        guard store.overview == nil || store.isApproved else { return }
        carregandoLista = true
        defer { carregandoLista = false }
        do {
            automacoes = try await AutomacoesAPI.lista()
            listaCarregada = true
            erroDaLista = nil
        } catch is CancellationError {
            // troca de tela no meio — silencioso
        } catch {
            erroDaLista = (error as? APIError)?.message ?? "Não foi possível carregar as automações."
        }
    }

    private func carregarCalendario() async {
        guard store.overview == nil || store.isApproved else { return }
        let a = ano, m = mes
        carregandoCalendario = true
        defer { carregandoCalendario = false }
        do {
            let resposta = try await AutomacoesAPI.calendario(
                de: AutDia.iso(a, m, 1),
                ate: AutDia.iso(a, m, AutDia.diasNoMes(a, m))
            )
            // O terapeuta pode ter trocado de mês enquanto a resposta vinha.
            guard a == ano, m == mes else { return }
            datas = resposta
            erroDoCalendario = nil
        } catch is CancellationError {
            // troca de mês no meio — silencioso
        } catch {
            erroDoCalendario = (error as? APIError)?.message ?? "Não foi possível carregar o calendário."
        }
    }

    private func alterarData(
        _ item: AutDataDaAutomacao,
        chave: String,
        mensagem: String,
        chamada: () async throws -> Void
    ) async {
        acaoDaDataEmVoo = "\(item.id)-\(chave)"
        defer { acaoDaDataEmVoo = nil }
        do {
            try await chamada()
            Haptics.success()
            mudandoValorDe = nil
            toast = AgendaToastData(message: mensagem, showUndo: false)
            await recarregarTudo()
        } catch is CancellationError {
        } catch {
            Haptics.warning()
            erro = (error as? APIError)?.message ?? "Não foi possível alterar esta data."
        }
    }

    private func acaoNaLista(_ a: Automacao, _ tipo: String) async {
        acaoDaListaEmVoo = "\(a.id)-\(tipo)"
        defer { acaoDaListaEmVoo = nil }
        do {
            switch tipo {
            case "pausar": try await AutomacoesAPI.pausar(id: a.id)
            case "retomar": try await AutomacoesAPI.retomar(id: a.id)
            default: try await AutomacoesAPI.excluir(id: a.id)
            }
            Haptics.success()
            let mensagem = switch tipo {
            case "pausar": "Automação pausada. Nenhuma cobrança sai até você retomar."
            case "retomar": "Automação retomada. As próximas datas voltam a sair."
            default: "Automação excluída. As cobranças já criadas continuam."
            }
            toast = AgendaToastData(message: mensagem, showUndo: false)
            await recarregarTudo()
        } catch is CancellationError {
        } catch {
            Haptics.warning()
            erro = (error as? APIError)?.message ?? "Não foi possível alterar a automação."
        }
    }

    /// "Ver cobrança": a lista de cobranças do paciente já traz o objeto que a
    /// tela de detalhe espera (não há rota de uma cobrança só).
    private func abrirCobranca(_ item: AutDataDaAutomacao, chargeId: String) async {
        acaoDaDataEmVoo = "\(item.id)-ver"
        defer { acaoDaDataEmVoo = nil }
        do {
            let cobrancas = try await FinanceAPI.charges(patientId: item.patient.id)
            if let charge = cobrancas.first(where: { $0.id == chargeId }) {
                cobrancaAberta = CobrancaAberta(charge: charge)
            } else {
                erro = "Não encontramos esta cobrança. Ela pode ter sido excluída."
            }
        } catch is CancellationError {
        } catch {
            erro = (error as? APIError)?.message ?? "Não foi possível abrir a cobrança."
        }
    }
}
