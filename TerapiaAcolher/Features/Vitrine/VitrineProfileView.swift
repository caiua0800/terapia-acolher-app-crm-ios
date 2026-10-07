import Observation
import SwiftUI

@Observable
final class VitrineProfileViewModel {
    var perfil: VitrineProfile?
    var options: VitrineOptions?

    var name = ""
    var bio = ""
    var city = ""
    var state = ""
    var whatsapp = ""
    var priceText = ""
    var specialties: Set<String> = []
    var approaches: Set<String> = []
    var targetAudience: Set<String> = []
    var shifts: Set<String> = []
    var modalities: Set<String> = []
    var languages: Set<String> = []

    var isLoading = true
    var isSaving = false
    var errorMessage: String?
    var alerta: String?
    var showAlerta = false
    var salvou = false

    /// Limite da bio na Vitrine. Deixar o terapeuta escrever 3.000 caracteres
    /// e só descobrir no "salvar" é o pior momento pra avisar.
    static let bioMax = 1000
    /// A Vitrine só conta a apresentação como feita a partir de 80 caracteres.
    static let bioMin = 80

    var bioFaltam: Int {
        max(0, Self.bioMin - bio.trimmingCharacters(in: .whitespacesAndNewlines).count)
    }

    /// Retrato do que veio da Vitrine: o "Salvar" só aparece quando algo mudou.
    private var original = ""

    private var assinatura: String {
        [name, bio, city, state, whatsapp, priceText,
         specialties.sorted().joined(separator: "|"),
         approaches.sorted().joined(separator: "|"),
         targetAudience.sorted().joined(separator: "|"),
         shifts.sorted().joined(separator: "|"),
         modalities.sorted().joined(separator: "|"),
         languages.sorted().joined(separator: "|")].joined(separator: "§")
    }

    var alterado: Bool { !isLoading && errorMessage == nil && assinatura != original }

    private func marcarComoSalvo() { original = assinatura }

    /// Mesmos itens do "Complete seu perfil" da tela da Vitrine.
    var itensDoPerfil: [(String, Bool)] {
        [
            ("Foto", perfil?.photoUrl?.isEmpty == false),
            ("Apresentação", bioFaltam == 0),
            ("Especialidades", !specialties.isEmpty),
            ("Abordagem", !approaches.isEmpty),
            ("Público atendido", !targetAudience.isEmpty),
            ("Modalidade", !modalities.isEmpty),
            ("Turnos", !shifts.isEmpty),
            ("Cidade e estado", !city.isEmpty && !state.isEmpty),
            ("WhatsApp", !whatsapp.isEmpty),
            ("Valor da consulta", price != nil),
        ]
    }

    var percentualCompleto: Int {
        let itens = itensDoPerfil
        return Int((Double(itens.filter(\.1).count) / Double(itens.count) * 100).rounded())
    }

    @MainActor
    func load() async {
        isLoading = perfil == nil
        errorMessage = nil
        do {
            async let p = VitrineAPI.profile()
            async let o = VitrineAPI.options()
            let (perfil, options) = try await (p, o)
            self.perfil = perfil
            self.options = options
            preencher(perfil)
            marcarComoSalvo()
        } catch is CancellationError {
        } catch let error as APIError {
            errorMessage = error.message
            if error.code == VitrineViewModel.codigoRevogada {
                await VitrineViewModel.shared.handleRevoked()
            }
        } catch {
            errorMessage = "Não foi possível carregar seu perfil da Vitrine."
        }
        isLoading = false
    }

    private func preencher(_ p: VitrineProfile) {
        name = p.name ?? ""
        bio = p.bio ?? ""
        city = p.city ?? ""
        state = p.state ?? ""
        whatsapp = p.whatsapp ?? ""
        priceText = p.consultationPrice.map { String(format: "%.2f", $0).replacingOccurrences(of: ".", with: ",") } ?? ""
        specialties = Set(p.specialties ?? [])
        approaches = Set(p.approaches ?? [])
        targetAudience = Set(p.targetAudience ?? [])
        shifts = Set(p.shifts ?? [])
        modalities = Set(p.modalities ?? [])
        languages = Set(p.languages?.itens ?? [])
    }

    var price: Double? {
        let limpo = priceText
            .replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return limpo.isEmpty ? nil : Double(limpo)
    }

    @MainActor
    func save() async -> Bool {
        if !priceText.isEmpty && price == nil {
            present("Valor da consulta inválido.")
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            // Só o que o formulário mostra. Mandar o objeto inteiro faria o app
            // sobrescrever, com dado velho, campos que ele nem exibe.
            try await VitrineAPI.save(
                VitrineProfilePatch(
                    name: name.trimmingCharacters(in: .whitespaces),
                    bio: bio,
                    state: state.isEmpty ? nil : state,
                    city: city.isEmpty ? nil : city,
                    whatsapp: whatsapp.isEmpty ? nil : whatsapp,
                    modalities: Array(modalities),
                    specialties: Array(specialties),
                    targetAudience: Array(targetAudience),
                    shifts: Array(shifts),
                    approaches: Array(approaches),
                    languages: Array(languages),
                    consultationPrice: price
                )
            )
            Haptics.success()
            salvou = true
            marcarComoSalvo()
            return true
        } catch let error as APIError {
            // A validação de verdade é a da Vitrine — ela é dona do dado.
            // Mostramos a mensagem dela, não uma genérica nossa.
            present(error.message)
            if error.code == VitrineViewModel.codigoRevogada {
                await VitrineViewModel.shared.handleRevoked()
            }
        } catch {
            present("Não foi possível salvar. Verifique sua conexão.")
        }
        return false
    }

    @MainActor
    private func present(_ mensagem: String) {
        alerta = mensagem
        showAlerta = true
    }
}

/// Edição do perfil da Vitrine. A Vitrine continua DONA do dado: aqui não há
/// cópia local, o formulário carrega dela e salva nela. Sem cópia não existe
/// sincronização, e sem sincronização não existe conflito.
///
/// Redesenho (2026-10-07): foto em destaque com % do perfil completo, prévia de
/// como o paciente vê, seções numeradas, chips com busca nas listas longas e
/// "Salvar" fixo embaixo só quando algo mudou. A foto em si é trocada no portal
/// da Vitrine (a API do CRM não tem envio de foto).
struct VitrineProfileView: View {
    @State private var model = VitrineProfileViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()
            content
            if model.alterado {
                barraSalvar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.alterado)
        .setToolbarTitle("Meu perfil na Vitrine")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .alert("Ops", isPresented: $model.showAlerta) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alerta ?? "Algo deu errado.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            esqueleto
        } else if let erro = model.errorMessage {
            ErrorRetryView(message: erro) { Task { await model.load() } }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    topo
                    previa
                    secao(1, "Foto e apresentação", "O que o paciente lê primeiro.") {
                        campo("Nome", texto: $model.name)
                        bioEditor
                    }
                    secao(2, "Como você atende", "Ajuda o paciente a achar você na busca.") {
                        grupo("Especialidades", opcoes: model.options?.specialties, selecao: $model.specialties)
                        grupo("Abordagens", opcoes: model.options?.approaches, selecao: $model.approaches)
                        grupo("Público atendido", opcoes: model.options?.targetAudience, selecao: $model.targetAudience)
                        grupo("Modalidade", opcoes: model.options?.modalities, selecao: $model.modalities)
                        grupo("Idiomas", opcoes: model.options?.languages, selecao: $model.languages)
                    }
                    secao(3, "Onde e quando", "Cidade e horários em que você atende.") {
                        HStack(alignment: .top, spacing: 10) {
                            campo("Cidade", texto: $model.city)
                            campo("UF", texto: $model.state, maiusculo: true)
                                .frame(width: 88)
                        }
                        grupo("Turnos", opcoes: model.options?.shifts, selecao: $model.shifts)
                    }
                    secao(4, "Contato e valor", "Por onde o paciente chama e quanto custa.") {
                        campo("WhatsApp", texto: $model.whatsapp, teclado: .phonePad)
                        VStack(alignment: .leading, spacing: 6) {
                            rotulo("Valor da consulta")
                            CampoDinheiro(texto: $model.priceText, fonte: Theme.body(16))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                        }
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, model.alterado ? 112 : 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: Topo: foto + perfil completo

    private var fotoURL: URL? {
        model.perfil?.photoUrl.flatMap(URL.init(string:)) ?? VitrineViewModel.shared.crmAvatarURL
    }

    private var nomeExibido: String { model.name.isEmpty ? "?" : model.name }

    private var topo: some View {
        ThemeCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                LinearGradient(
                    colors: [Color(hex: 0xCFE3D3), Color(hex: 0xE7F0EA), Color(hex: 0xF3E7D6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 72)

                HStack(alignment: .bottom, spacing: 14) {
                    RemoteAvatar(url: fotoURL, name: nomeExibido, size: 96)
                        .overlay(Circle().stroke(Color.white, lineWidth: 4))
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                        .padding(.top, -48)
                    medidor
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)

                if model.perfil?.photoUrl?.isEmpty != false {
                    Text("Sem foto na Vitrine: o paciente vê sua foto do Acolher Gestão. A foto do perfil público é trocada no portal da Vitrine.")
                        .font(Theme.body(11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                }

                pendencias
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
            }
        }
    }

    private var medidor: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Theme.border, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(model.percentualCompleto) / 100)
                    .stroke(
                        model.percentualCompleto == 100 ? Theme.success : Theme.warning,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(model.percentualCompleto)%")
                    .font(Theme.body(11, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 46, height: 46)
            .animation(.easeOut(duration: 0.4), value: model.percentualCompleto)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.percentualCompleto == 100 ? "Perfil completo" : "Complete seu perfil")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Perfis completos aparecem melhor na busca.")
                    .font(Theme.body(11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private var pendencias: some View {
        let faltam = model.itensDoPerfil.filter { !$0.1 }.map(\.0)
        if !faltam.isEmpty {
            FlexibleStack(faltam, spacing: 6) { item in
                HStack(spacing: 4) {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 10, weight: .semibold))
                    Text(item == "Apresentação" && model.bioFaltam > 0 && !model.bio.isEmpty
                         ? "Apresentação (faltam \(model.bioFaltam))" : item)
                }
                .font(Theme.body(11.5, weight: .medium))
                .foregroundStyle(Theme.warning)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Theme.warningSoft, in: Capsule())
            }
        }
    }

    // MARK: Prévia: como o paciente vê

    private var previa: some View {
        VStack(alignment: .leading, spacing: 8) {
            rotulo("Como o paciente vê")
            ThemeCard {
                HStack(alignment: .top, spacing: 12) {
                    RemoteAvatar(url: fotoURL, name: nomeExibido, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.name.isEmpty ? "Seu nome" : model.name)
                            .font(Theme.serifTitle(18))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        let local = [model.city, model.state].filter { !$0.isEmpty }.joined(separator: " / ")
                        if !local.isEmpty {
                            Label(local, systemImage: "mappin.and.ellipse")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        let especialidades = model.specialties.sorted()
                        if !especialidades.isEmpty {
                            let mostrar = Array(especialidades.prefix(3))
                                + (especialidades.count > 3 ? ["+\(especialidades.count - 3)"] : [])
                            FlexibleStack(mostrar, spacing: 5) { e in
                                Text(e)
                                    .font(Theme.body(11, weight: .medium))
                                    .foregroundStyle(Theme.primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Theme.primarySoft, in: Capsule())
                            }
                            .padding(.top, 2)
                        }
                        if !model.languages.isEmpty {
                            Label(model.languages.sorted().joined(separator: ", "), systemImage: "globe")
                                .font(Theme.body(11.5))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        if let preco = model.price {
                            Text("Consulta \(Formatters.brl(preco))")
                                .font(Theme.body(12.5, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Peças

    private func secao<Conteudo: View>(
        _ numero: Int,
        _ titulo: String,
        _ subtitulo: String,
        @ViewBuilder conteudo: () -> Conteudo
    ) -> some View {
        let corpo = conteudo()
        return ThemeCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    Text("\(numero)")
                        .font(Theme.body(12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Theme.ink, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(titulo)
                            .font(Theme.serifTitle(18))
                            .foregroundStyle(Theme.textPrimary)
                        Text(subtitulo)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                corpo
            }
        }
    }

    private func rotulo(_ texto: String) -> some View {
        Text(texto.uppercased())
            .font(Theme.body(10.5, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(Theme.textSecondary)
    }

    private func campo(
        _ titulo: String,
        texto: Binding<String>,
        teclado: UIKeyboardType = .default,
        maiusculo: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            rotulo(titulo)
            TextField("", text: texto)
                .font(Theme.body(15))
                .keyboardType(teclado)
                .autocorrectionDisabled()
                .textInputAutocapitalization(maiusculo ? .characters : .words)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        }
    }

    private var contadorDaBio: String {
        let total = "\(model.bio.count)/\(VitrineProfileViewModel.bioMax)"
        return model.bioFaltam > 0 ? "faltam \(model.bioFaltam) · \(total)" : total
    }

    private var corDoContador: Color {
        if model.bio.count > VitrineProfileViewModel.bioMax { return Theme.danger }
        if model.bioFaltam > 0 || model.bio.count > VitrineProfileViewModel.bioMax - 100 { return Theme.warning }
        return Theme.textSecondary
    }

    private var bioEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                rotulo("Sobre você")
                Spacer()
                Text(contadorDaBio)
                    .font(Theme.body(11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(corDoContador)
            }
            ZStack(alignment: .topLeading) {
                if model.bio.isEmpty {
                    Text("Conte como você trabalha, para quem é a sua terapia e o que o paciente pode esperar da primeira sessão.")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary.opacity(0.8))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $model.bio)
                    .font(Theme.body(15))
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
            }
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
            if model.bioFaltam > 0 {
                // O aviso vale mais que o campo: perfil sem apresentação é o que
                // mais custa clique, e a Vitrine só conta a partir de 80.
                Text("Escreva pelo menos \(VitrineProfileViewModel.bioMin) caracteres — faltam \(model.bioFaltam). Perfis com apresentação recebem bem mais contatos.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func grupo(
        _ titulo: String,
        opcoes: [String]?,
        selecao: Binding<Set<String>>
    ) -> some View {
        // As listas vêm da Vitrine. NUNCA redeclarar aqui — foi assim que a
        // opção "Outra" sumiu do cadastro no sistema antigo deles.
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                rotulo(titulo)
                Spacer()
                let n = selecao.wrappedValue.count
                if n > 0 {
                    Text("\(n) escolhida\(n == 1 ? "" : "s")")
                        .font(Theme.body(11, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                }
            }
            if let opcoes, !opcoes.isEmpty {
                ChipsComBusca(opcoes: opcoes, selecao: selecao, titulo: titulo)
            } else {
                Text("Não foi possível carregar as opções.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: Salvar fixo

    private var barraSalvar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Alterações não salvas")
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Vão direto para o seu perfil público.")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                Haptics.tap()
                Task {
                    if await model.save() { dismiss() } else { Haptics.warning() }
                }
            } label: {
                HStack(spacing: 6) {
                    if model.isSaving {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                    }
                    Text("Salvar")
                }
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Theme.primary, in: Capsule())
            }
            .buttonStyle(.pressable)
            .disabled(model.isSaving)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    // MARK: Carregando

    private var esqueleto: some View {
        ScrollView {
            VStack(spacing: 18) {
                ForEach(0 ..< 4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .fill(Theme.border.opacity(0.55))
                        .frame(height: i == 0 ? 170 : 130)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 12)
        }
        .allowsHitTesting(false)
    }
}

/// Chips com as escolhidas em cima. Listas longas (mais de 10 opções) ganham
/// busca sem acento e mostram 12 de cada vez, com "Ver todas".
struct ChipsComBusca: View {
    let opcoes: [String]
    @Binding var selecao: Set<String>
    let titulo: String
    @State private var busca = ""
    @State private var verTodas = false

    private static let visiveis = 12
    private var comBusca: Bool { opcoes.count > 10 }

    private func normalizar(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
    }

    private var naoEscolhidas: [String] {
        let q = normalizar(busca.trimmingCharacters(in: .whitespaces))
        let base = q.isEmpty ? opcoes : opcoes.filter { normalizar($0).contains(q) }
        return base.filter { !selecao.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let escolhidas = opcoes.filter { selecao.contains($0) }
            if !escolhidas.isEmpty {
                FlowChips(opcoes: escolhidas, selecao: $selecao)
            }
            if comBusca {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.textSecondary)
                    TextField("Buscar em \(titulo.lowercased())…", text: $busca)
                        .font(Theme.body(14))
                        .autocorrectionDisabled()
                    if !busca.isEmpty {
                        Button { busca = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
            }
            let lista = naoEscolhidas
            let mostrar = (!comBusca || verTodas || !busca.isEmpty) ? lista : Array(lista.prefix(Self.visiveis))
            if mostrar.isEmpty, !busca.isEmpty {
                Text("Nada encontrado para “\(busca)”.")
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.textSecondary)
            } else if !mostrar.isEmpty {
                FlowChips(opcoes: mostrar, selecao: $selecao)
            }
            if comBusca, busca.isEmpty, lista.count > Self.visiveis {
                Button {
                    Haptics.tap()
                    withAnimation(.easeOut(duration: 0.2)) { verTodas.toggle() }
                } label: {
                    Text(verTodas ? "Mostrar menos" : "Ver todas (\(lista.count))")
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Chips que quebram linha sozinhos.
struct FlowChips: View {
    let opcoes: [String]
    @Binding var selecao: Set<String>

    var body: some View {
        FlexibleStack(opcoes, spacing: 8) { opcao in
            let ativo = selecao.contains(opcao)
            Button {
                Haptics.tap()
                if ativo { selecao.remove(opcao) } else { selecao.insert(opcao) }
            } label: {
                Text(opcao)
                    .font(Theme.body(13, weight: ativo ? .semibold : .regular))
                    .foregroundStyle(ativo ? Theme.primary : Theme.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(ativo ? Theme.primarySoft : Theme.background, in: Capsule())
                    .overlay(
                        Capsule().stroke(ativo ? Theme.primary : Theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.pressable)
        }
    }
}

/// Layout que empilha em linhas conforme a largura disponível.
struct FlexibleStack<Item: Hashable, Conteudo: View>: View {
    let itens: [Item]
    let spacing: CGFloat
    let conteudo: (Item) -> Conteudo

    init(_ itens: [Item], spacing: CGFloat = 8, @ViewBuilder conteudo: @escaping (Item) -> Conteudo) {
        self.itens = itens
        self.spacing = spacing
        self.conteudo = conteudo
    }

    var body: some View {
        FlowLayout(spacing: spacing) {
            ForEach(itens, id: \.self) { conteudo($0) }
        }
    }
}

/// `Layout` nativo: mede cada chip e quebra a linha quando não cabe.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largura = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, alturaLinha: CGFloat = 0
        for sub in subviews {
            let t = sub.sizeThatFits(.unspecified)
            if x + t.width > largura, x > 0 {
                x = 0
                y += alturaLinha + spacing
                alturaLinha = 0
            }
            x += t.width + spacing
            alturaLinha = max(alturaLinha, t.height)
        }
        return CGSize(width: largura, height: y + alturaLinha)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, alturaLinha: CGFloat = 0
        for sub in subviews {
            let t = sub.sizeThatFits(.unspecified)
            if x + t.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += alturaLinha + spacing
                alturaLinha = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + spacing
            alturaLinha = max(alturaLinha, t.height)
        }
    }
}
