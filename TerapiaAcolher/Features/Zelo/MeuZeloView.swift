import SwiftUI

// MARK: - Estado

/// "Meu Zelo AI" (2026-10-06). Guarda a versão salva e o rascunho: o botão
/// Salvar só aparece quando os dois diferem.
@MainActor
@Observable
final class MeuZeloStore {
    var salvo: ZeloConfig?
    var rascunho = ZeloConfig()
    var carregando = false
    var salvando = false
    var erro: String?
    var aviso: String?
    var previa: ZeloBomDiaPrevia?
    var carregandoPrevia = false
    var erroPrevia: String?

    var alterado: Bool {
        guard let salvo else { return false }
        return salvo.genero != rascunho.genero
            || salvo.personalidade != rascunho.personalidade
            || salvo.jeitoDeFalar != rascunho.jeitoDeFalar
            || salvo.bomDia != rascunho.bomDia
    }

    func carregar() async {
        carregando = salvo == nil
        defer { carregando = false }
        do {
            let c: ZeloConfig = try await APIClient.shared.get("zelo/config")
            salvo = c
            rascunho = c
            erro = nil
        } catch {
            erro = (error as? APIError)?.message ?? "Não foi possível carregar o seu Zelo."
        }
    }

    @discardableResult
    func salvar() async -> Bool {
        guard !salvando else { return false }
        salvando = true
        defer { salvando = false }
        do {
            let envio = ZeloConfigEnvio(
                genero: rascunho.genero,
                personalidade: rascunho.personalidade,
                jeitoDeFalar: rascunho.jeitoDeFalar,
                bomDia: rascunho.bomDia
            )
            let c: ZeloConfig = try await APIClient.shared.put("zelo/config", body: envio)
            salvo = c
            rascunho = c
            aviso = nil
            return true
        } catch {
            aviso = (error as? APIError)?.message ?? "Não foi possível salvar. Tente de novo."
            return false
        }
    }

    func carregarPrevia() async {
        carregandoPrevia = true
        erroPrevia = nil
        defer { carregandoPrevia = false }
        do {
            previa = try await APIClient.shared.get("zelo/bom-dia/previa")
        } catch {
            erroPrevia = (error as? APIError)?.message ?? "Não foi possível montar a prévia."
        }
    }

    /// Marca/desmarca respeitando o limite e os pares que se excluem.
    /// Devolve um aviso curto quando desmarcou o conflito.
    func alternar(_ chave: String, em lista: ReferenceWritableKeyPath<MeuZeloStore, [String]>, limite: Int) -> String? {
        var atual = self[keyPath: lista]
        if let i = atual.firstIndex(of: chave) {
            atual.remove(at: i)
            self[keyPath: lista] = atual
            return nil
        }
        var avisoConflito: String?
        for par in rascunho.opcoes.conflitos where par.contains(chave) {
            for outra in par where outra != chave {
                if let j = atual.firstIndex(of: outra) {
                    atual.remove(at: j)
                    let rotulo = (rascunho.opcoes.personalidade + rascunho.opcoes.jeitoDeFalar)
                        .first { $0.chave == outra }?.rotulo ?? outra
                    avisoConflito = "Tirei \"\(rotulo)\": não combina com esta."
                }
            }
        }
        guard atual.count < limite else { return "Escolha até \(limite)." }
        atual.append(chave)
        self[keyPath: lista] = atual
        return avisoConflito
    }

    var personalidadeSel: [String] {
        get { rascunho.personalidade }
        set { rascunho.personalidade = newValue }
    }

    var jeitoSel: [String] {
        get { rascunho.jeitoDeFalar }
        set { rascunho.jeitoDeFalar = newValue }
    }
}

// MARK: - Tela

struct MeuZeloView: View {
    @State private var store = MeuZeloStore()
    @State private var buscaPersonalidade = ""
    @State private var buscaJeito = ""
    @State private var avisoChip: String?
    @State private var mostrandoPrevia = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if store.salvo != nil {
                conteudo
            } else if store.carregando {
                ProgressView().tint(Theme.primary)
            } else if let erro = store.erro {
                VStack(spacing: 14) {
                    EmptyStateView(icon: "sparkles", title: "Ops, não carregou", message: erro)
                    RetryButton(isLoading: store.carregando) {
                        Task { await store.carregar() }
                    }
                }
                .padding()
            }
        }
        .safeAreaInset(edge: .bottom) { barraSalvar }
        .task { await store.carregar() }
        .sheet(isPresented: $mostrandoPrevia) { previaSheet }
    }

    private var conteudo: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                cabecalho
                quemEOZelo
                bomDia
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var cabecalho: some View {
        HStack(spacing: 14) {
            ZeloAvatar(size: 52)
            VStack(alignment: .leading, spacing: 3) {
                (Text("Configure o seu ") + Zelo.nomeEstilizado(22))
                    .font(Theme.serifTitle(22))
                    .foregroundStyle(Theme.textPrimary)
                Text("Do jeito dele falar ao bom dia de cada manhã.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: Quem é o seu Zelo

    private var quemEOZelo: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 16) {
                tituloSecao("Quem é o seu Zelo", "Muda só o tom. As regras de segurança do Zelo continuam as mesmas.")

                VStack(alignment: .leading, spacing: 8) {
                    rotulo("Como o Zelo se apresenta")
                    Picker("Gênero", selection: $store.rascunho.genero) {
                        Text("Masculino · o Zelo").tag("M")
                        Text("Feminino · a Zelo").tag("F")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: store.rascunho.genero) { Haptics.tap() }
                }

                seletor(
                    titulo: "Personalidade",
                    opcoes: store.rascunho.opcoes.personalidade,
                    selecionadas: store.rascunho.personalidade,
                    limite: store.rascunho.limites.personalidade,
                    busca: $buscaPersonalidade,
                    caminho: \.personalidadeSel
                )

                seletor(
                    titulo: "Jeito de falar",
                    opcoes: store.rascunho.opcoes.jeitoDeFalar,
                    selecionadas: store.rascunho.jeitoDeFalar,
                    limite: store.rascunho.limites.jeitoDeFalar,
                    busca: $buscaJeito,
                    caminho: \.jeitoSel
                )

                if let avisoChip {
                    Text(avisoChip)
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.warning)
                        .transition(.opacity)
                }

                VStack(alignment: .leading, spacing: 8) {
                    rotulo("Assim o seu Zelo fala")
                    balao(fraseDeExemplo)
                }
            }
        }
    }

    private func seletor(
        titulo: String,
        opcoes: [ZeloTraco],
        selecionadas: [String],
        limite: Int,
        busca: Binding<String>,
        caminho: ReferenceWritableKeyPath<MeuZeloStore, [String]>
    ) -> some View {
        let termo = busca.wrappedValue.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "pt_BR"))
        let filtradas = opcoes.filter { op in
            termo.isEmpty
                || op.rotulo.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "pt_BR")).contains(termo)
        }
        let cheio = selecionadas.count >= limite
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                rotulo(titulo)
                Spacer()
                Text("\(selecionadas.count) de \(limite)")
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(cheio ? Theme.primary : Theme.textSecondary)
                    .monospacedDigit()
            }
            if !selecionadas.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(selecionadas, id: \.self) { chave in
                        let rotuloOp = opcoes.first { $0.chave == chave }?.rotulo ?? chave
                        chip(rotuloOp, selecionado: true, desabilitado: false) {
                            avisoChip = store.alternar(chave, em: caminho, limite: limite)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                TextField("Buscar \(titulo.lowercased())", text: busca)
                    .font(Theme.body(14))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !busca.wrappedValue.isEmpty {
                    Button {
                        busca.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityLabel("Limpar busca")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))

            let naoSelecionadas = filtradas.filter { !selecionadas.contains($0.chave) }
            if naoSelecionadas.isEmpty {
                Text(termo.isEmpty ? "Você escolheu todas." : "Nada com \"\(busca.wrappedValue)\".")
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(naoSelecionadas) { op in
                        chip(op.rotulo, selecionado: false, desabilitado: cheio) {
                            avisoChip = store.alternar(op.chave, em: caminho, limite: limite)
                        }
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: selecionadas)
    }

    private func chip(_ texto: String, selecionado: Bool, desabilitado: Bool, acao: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            acao()
        } label: {
            HStack(spacing: 5) {
                Text(texto)
                if selecionado {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .font(Theme.body(13.5, weight: selecionado ? .semibold : .regular))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .foregroundStyle(selecionado ? Color.white : Theme.textPrimary)
            .background(selecionado ? Zelo.cor : Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(selecionado ? Color.clear : Theme.border, lineWidth: 1))
            .opacity(desabilitado ? 0.4 : 1)
        }
        .buttonStyle(.pressable)
        .disabled(desabilitado)
        .accessibilityAddTraits(selecionado ? .isSelected : [])
    }

    /// Frase de exemplo montada aqui, sem IA: só mostra o efeito das escolhas.
    private var fraseDeExemplo: String {
        let r = store.rascunho
        let feminino = r.genero == "F"
        let jeito = Set(r.jeitoDeFalar)
        let perso = Set(r.personalidade)
        let formal = jeito.contains("mais_formal")
        let curto = jeito.contains("respostas_curtas") || jeito.contains("direto_ao_ponto")
        let emoji = jeito.contains("usa_emojis_com_moderacao")
        let animado = !perso.isDisjoint(with: ["animado", "entusiasmado", "bem_humorado", "otimista", "motivador"])
        let acolhedor = !perso.isDisjoint(with: ["acolhedor", "caloroso", "empatico", "gentil", "atencioso"])

        let saudacao = formal ? "Bom dia, Ana." : (animado ? "Bom dia, Ana!" : "Oi, Ana!")
        let apresentacao = feminino ? "Aqui é a Zelo" : "Aqui é o Zelo"
        let corpo = curto
            ? "Hoje: 3 sessões, a primeira às 9h."
            : "Vi aqui que você tem 3 sessões hoje, a primeira às 9h com a Marina."
        let fecho = acolhedor
            ? "Conte comigo, estou por aqui."
            : (animado ? "Vai ser um ótimo dia!" : (feminino ? "Fico atenta por aqui." : "Fico atento por aqui."))
        return "\(saudacao) \(apresentacao). \(corpo) \(fecho)\(emoji ? " 🌿" : "")"
    }

    // MARK: Bom dia do Zelo

    private var bomDia: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 16) {
                tituloSecao("Bom dia do Zelo", "Todo dia, na hora que você acorda, um resumo do seu dia.")

                Toggle(isOn: $store.rascunho.bomDia.ativo.animation(.easeOut(duration: 0.2))) {
                    Text("Receber o bom dia do Zelo")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.primary)

                if !store.rascunho.canalDisponivel {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.warning)
                        Text("O WhatsApp do Zelo chega em breve. Sua configuração já fica salva.")
                            .font(Theme.body(12.5))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: 12))
                }

                if store.rascunho.bomDia.ativo {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            rotulo("Horário")
                            Spacer()
                            DatePicker("Horário", selection: horarioBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .environment(\.locale, Locale(identifier: "pt_BR"))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            rotulo("Dias da semana")
                            diasDaSemana
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            rotulo("O que o Zelo te conta")
                            itemBomDia("Sessões do dia", "Horário, primeiro nome e se é online.", disponivel: store.rascunho.disponiveis.sessoes, motivo: "", valor: $store.rascunho.bomDia.itens.sessoes)
                            itemBomDia("Compromissos da agenda", "Do Google Agenda, sem repetir as sessões.", disponivel: store.rascunho.disponiveis.agenda, motivo: "Conecte o Google Agenda", valor: $store.rascunho.bomDia.itens.agenda)
                            itemBomDia("Saldo na conta", "Disponível no Acolher Financeiro.", disponivel: store.rascunho.disponiveis.saldo, motivo: "Abra a sua conta no Acolher Financeiro", valor: $store.rascunho.bomDia.itens.saldo)
                            itemBomDia("A receber no mês", "Cobranças em aberto deste mês.", disponivel: store.rascunho.disponiveis.aReceberMes, motivo: "Indisponível no seu plano", valor: $store.rascunho.bomDia.itens.aReceberMes)
                            itemBomDia("Leads esperando contato", "Quantos ainda estão sem atendimento.", disponivel: store.rascunho.disponiveis.leadsPendentes, motivo: "Conecte seus leads", valor: $store.rascunho.bomDia.itens.leadsPendentes)
                            itemBomDia("Visualizações da Vitrine", "Ontem e nos últimos 7 dias.", disponivel: store.rascunho.disponiveis.vitrineVisualizacoes, motivo: "Disponível no plano Pró com a Vitrine conectada", valor: $store.rascunho.bomDia.itens.vitrineVisualizacoes)
                        }

                        Button {
                            Haptics.tap()
                            mostrandoPrevia = true
                            Task { await store.carregarPrevia() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "eye")
                                Text("Ver como fica hoje")
                            }
                            .font(Theme.body(14, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.primarySoft, in: Capsule())
                        }
                        .buttonStyle(.pressable)
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private var horarioBinding: Binding<Date> {
        Binding {
            let partes = store.rascunho.bomDia.horario.split(separator: ":").compactMap { Int($0) }
            var c = DateComponents()
            c.hour = partes.first ?? 7
            c.minute = partes.count > 1 ? partes[1] : 0
            return Calendar.current.date(from: c) ?? Date()
        } set: { nova in
            let c = Calendar.current.dateComponents([.hour, .minute], from: nova)
            store.rascunho.bomDia.horario = String(format: "%02d:%02d", c.hour ?? 7, c.minute ?? 0)
        }
    }

    private var diasDaSemana: some View {
        let letras = ["D", "S", "T", "Q", "Q", "S", "S"]
        let nomes = ["Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"]
        return HStack(spacing: 0) {
            ForEach(0 ..< 7, id: \.self) { dia in
                let ligado = store.rascunho.bomDia.dias.contains(dia)
                Button {
                    Haptics.tap()
                    var dias = store.rascunho.bomDia.dias
                    if let i = dias.firstIndex(of: dia) { dias.remove(at: i) } else { dias.append(dia) }
                    store.rascunho.bomDia.dias = dias.sorted()
                } label: {
                    Text(letras[dia])
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(ligado ? Color.white : Theme.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(ligado ? Theme.primary : Theme.surface, in: Circle())
                        .overlay(Circle().stroke(ligado ? Color.clear : Theme.border, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(nomes[dia])
                .accessibilityAddTraits(ligado ? .isSelected : [])
            }
        }
        .animation(.easeOut(duration: 0.15), value: store.rascunho.bomDia.dias)
    }

    private func itemBomDia(_ titulo: String, _ explicacao: String, disponivel: Bool, motivo: String, valor: Binding<Bool>) -> some View {
        Toggle(isOn: Binding {
            disponivel && valor.wrappedValue
        } set: { novo in
            valor.wrappedValue = novo
        }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                    .font(Theme.body(14.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(disponivel ? explicacao : motivo)
                    .font(Theme.body(12))
                    .foregroundStyle(disponivel ? Theme.textSecondary : Theme.warning)
            }
        }
        .tint(Theme.primary)
        .disabled(!disponivel)
        .opacity(disponivel ? 1 : 0.6)
        .padding(.vertical, 6)
    }

    // MARK: Prévia e salvar

    private var previaSheet: some View {
        NavigationStack {
            ZStack {
                Color(hex: 0xECE5DD).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if store.carregandoPrevia {
                            ProgressView().tint(Theme.primary).frame(maxWidth: .infinity).padding(.top, 40)
                        } else if let erro = store.erroPrevia {
                            Text(erro)
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.danger)
                                .padding()
                        } else if let previa = store.previa {
                            balao(previa.texto)
                            Text("É assim que o Zelo te mandaria hoje, com os dados de agora.")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Bom dia do Zelo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { mostrandoPrevia = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Balão no estilo WhatsApp: é por lá que a mensagem vai chegar.
    private func balao(_ texto: String) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZeloAvatar(size: 28)
            Text(texto)
                .font(Theme.body(14.5))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.white, in: UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 4, bottomTrailingRadius: 14, topTrailingRadius: 14))
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 24)
        }
    }

    @ViewBuilder
    private var barraSalvar: some View {
        if store.alterado || store.aviso != nil {
            VStack(spacing: 8) {
                if let aviso = store.aviso {
                    Text(aviso)
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.danger)
                }
                PrimaryButton(title: "Salvar", icon: "checkmark", isLoading: store.salvando, isEnabled: store.alterado) {
                    Task {
                        if await store.salvar() { Haptics.success() } else { Haptics.warning() }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func tituloSecao(_ titulo: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(titulo)
                .font(Theme.serifTitle(19))
                .foregroundStyle(Theme.textPrimary)
            Text(sub)
                .font(Theme.body(12.5))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func rotulo(_ texto: String) -> some View {
        Text(texto.uppercased())
            .font(Theme.body(10.5, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(Theme.textSecondary)
    }
}
