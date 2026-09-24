import Observation
import SwiftUI
import UIKit

@Observable
final class VitrineViewModel {
    /// Instância única: o estado sobrevive à navegação.
    ///
    /// Antes cada tela criava o seu view model como `@State` local, então ele
    /// MORRIA ao sair — voltar para cá dois segundos depois dava spinner e
    /// requisição de novo. Era o que mais fazia o app parecer lento, mesmo com
    /// a API respondendo rápido. Agora a tela volta com o conteúdo já pintado e
    /// só atualiza por baixo.
    /// `var`: o logout troca por uma instância nova (ver SessionScope).
    static var shared = VitrineViewModel()

    var status: VitrineStatus?
    /// Perfil publicado na Vitrine — o que o paciente vê.
    var profile: VitrineProfile?
    /// Foto do perfil no CRM: usada quando a Vitrine ainda não tem foto.
    var crmAvatarURL: URL?
    var isLoading = true
    var errorMessage: String?
    var isWorking = false
    var alerta: String?
    var showAlerta = false

    @MainActor
    func load() async {
        isLoading = status == nil
        errorMessage = nil
        do {
            let novo = try await VitrineAPI.status()
            status = novo
            if novo.connected, novo.indisponivel != true {
                // Complementos: falhar neles não derruba a tela.
                async let perfil = try? VitrineAPI.profile()
                async let avatar: SetImageURL? = try? APIClient.shared.get("settings/avatar")
                profile = await perfil ?? profile
                crmAvatarURL = await avatar?.url.flatMap(URL.init(string:)) ?? crmAvatarURL
            }
        } catch is CancellationError {
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar sua Vitrine."
        }
        isLoading = false
    }

    /// "Agora não" no convite do Início: some na hora; se a API falhar, volta.
    @MainActor
    func dismissInvite() async {
        let anterior = status?.inviteDismissed
        status?.inviteDismissed = true
        do {
            try await VitrineAPI.dismissInvite()
        } catch is CancellationError {
        } catch {
            status?.inviteDismissed = anterior
            // Sem alerta: o do store aparece na tela de leads/Vitrine, não
            // aqui. O convite voltar já diz que não salvou.
            Haptics.warning()
        }
    }

    @MainActor
    func connectURL() async -> URL? {
        isWorking = true
        defer { isWorking = false }
        do {
            return try await VitrineAPI.connectUrl()
        } catch let error as APIError {
            present(error.message)
        } catch {
            present("Não foi possível abrir a conexão com a Vitrine.")
        }
        return nil
    }

    @MainActor
    func disconnect() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await VitrineAPI.disconnect()
            status = try await VitrineAPI.status()
            Haptics.success()
        } catch let error as APIError {
            present(error.message)
        } catch {
            present("Não foi possível desconectar.")
        }
    }

    @MainActor
    private func present(_ mensagem: String) {
        alerta = mensagem
        showAlerta = true
    }
}

/// Vitrine Acolher dentro do CRM.
///
/// O ponto desta tela não é "mais um lugar para editar perfil" — é mostrar
/// RETORNO. O terapeuta paga a Vitrine todo mês e nunca vê se ela funciona;
/// visualizações e cliques respondem isso onde ele já abre todo dia.
struct VitrineView: View {
    @State private var model = VitrineViewModel.shared
    @State private var showDisconnect = false
    @State private var linkCopiado = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content
        }
        .setToolbarTitle("Vitrine")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        // O consentimento acontece no NAVEGADOR: quando o app volta a ficar
        // ativo, recarrega para refletir a conexão sem o terapeuta ter que
        // puxar a tela. Sem isso, ele conecta e o app continua dizendo que não.
        .onChange(of: scenePhase) { _, fase in
            if fase == .active { Task { await model.load() } }
        }
        .alert("Ops", isPresented: $model.showAlerta) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alerta ?? "Algo deu errado.")
        }
        .confirmationDialog(
            "Desconectar a Vitrine?",
            isPresented: $showDisconnect,
            titleVisibility: .visible
        ) {
            Button("Desconectar", role: .destructive) {
                Task { await model.disconnect() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Seu perfil continua no ar. Você só deixa de ver os números aqui.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView().tint(Theme.primary)
        } else if let erro = model.errorMessage {
            ErrorRetryView(message: erro) { Task { await model.load() } }
        } else if let status = model.status {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !status.configured {
                        indisponivelCard
                    } else if status.connected {
                        conectado(status)
                    } else {
                        convite
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .refreshable { await model.load() }
        }
    }

    // MARK: Não conectado

    private var convite: some View {
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 68, height: 68)
                    .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 18))

                Text("Sua Vitrine aqui dentro")
                    .font(Theme.serifTitle(21))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Conecte seu perfil para acompanhar quantas pessoas viram você e quantas chamaram no WhatsApp.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 20)

            PrimaryButton(
                title: "Conectar minha Vitrine",
                icon: "arrow.up.right",
                isLoading: model.isWorking
            ) {
                Task {
                    if let url = await model.connectURL() { openURL(url) }
                }
            }

            Text("Você confirma no site da Vitrine e volta pra cá. Não precisa copiar nada.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var indisponivelCard: some View {
        ThemeCard {
            Text("A integração com a Vitrine ainda não está habilitada neste ambiente.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Conectado

    @ViewBuilder
    private func conectado(_ status: VitrineStatus) -> some View {
        if status.indisponivel == true {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
                Text("Não conseguimos falar com a Vitrine agora. Seu perfil continua no ar — os números voltam assim que ela responder.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            botaoEditar(cheio: true)
        } else {
            cabecalho(status)
            numeros(status)
            if let p = model.profile {
                completude(p)
                sobreVoce(p)
                comoAtende(p)
                if let link = linkPublico(status) { seuLink(link, nome: p.name ?? "") }
            } else {
                ThemeCard {
                    Text("Não foi possível carregar os detalhes do seu perfil agora.")
                        .font(Theme.body(13.5))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        Button {
            showDisconnect = true
        } label: {
            Text("Desconectar a Vitrine deste app")
                .font(Theme.body(13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .disabled(model.isWorking)
        .padding(.top, 4)
    }

    private func linkPublico(_ status: VitrineStatus) -> URL? {
        guard let slug = model.profile?.slug ?? status.slug else { return nil }
        return URL(string: "https://vitrine.terapiaacolher.com.br/terapeuta/\(slug)")
    }

    // MARK: Cabeçalho do perfil

    private func cabecalho(_ status: VitrineStatus) -> some View {
        let p = model.profile
        let foto = p?.photoUrl.flatMap(URL.init(string:)) ?? model.crmAvatarURL
        let nome = (p?.name?.isEmpty == false ? p?.name : nil) ?? SessionStore.shared.user?.name ?? ""
        let local = [p?.city, p?.state].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " / ")
        let subtitulo = [p?.crp.map { "CRP \($0)" }, local.isEmpty ? nil : local].compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [Color(hex: 0xCFE3D3), Color(hex: 0xE7F0EA), Color(hex: 0xE2D9F3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 104)
                HStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Circle().fill(status.perfilAtivo == true ? Theme.success : Theme.warning).frame(width: 7, height: 7)
                        Text(status.perfilAtivo == true ? "NO AR" : "OCULTO")
                    }
                    .font(Theme.body(10.5, weight: .bold))
                    .foregroundStyle(status.perfilAtivo == true ? Theme.success : Theme.warning)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.white, in: Capsule())
                    Text(status.plano?.tipo == "FREE" ? "Plano gratuito" : "Plano \(status.planoLegivel)")
                        .font(Theme.body(10.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.85), in: Capsule())
                }
                .padding(12)
            }

            VStack(alignment: .leading, spacing: 12) {
                RemoteAvatar(url: foto, name: nome.isEmpty ? "?" : nome, size: 100)
                    .padding(5)
                    .background(Theme.surface, in: Circle())
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
                    .padding(.top, -56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(nome.isEmpty ? "Seu perfil" : nome)
                        .font(Theme.serifTitle(25))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitulo.isEmpty ? "Complete seus dados profissionais na edição do perfil" : subtitulo)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                    if let expira = status.plano?.expiraEm {
                        Text("Renova em \(PatientFormat.fullDate.string(from: expira))")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                FlowLayout(spacing: 6) {
                    if let preco = p?.consultationPrice, preco > 0 {
                        pilula("Consulta \(Formatters.brl(preco))", destaque: true)
                    }
                    ForEach(p?.modalities ?? [], id: \.self) { pilula(legivel($0)) }
                    if let zap = p?.whatsapp, !zap.isEmpty {
                        pilula(PatientMask.whatsapp(zap), icone: "phone.fill")
                    }
                }

                HStack(spacing: 8) {
                    if let link = linkPublico(status) {
                        Button {
                            Haptics.tap()
                            openURL(link)
                        } label: {
                            Label("Ver como o paciente vê", systemImage: "eye")
                                .font(Theme.body(14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Theme.primary, in: Capsule())
                        }
                        .buttonStyle(.pressable)
                    }
                    botaoEditar(cheio: linkPublico(status) == nil)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border, lineWidth: 1))
    }

    private func botaoEditar(cheio: Bool) -> some View {
        NavigationLink {
            VitrineProfileView()
        } label: {
            Label("Editar perfil", systemImage: "pencil")
                .font(Theme.body(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: cheio ? .infinity : nil)
                .padding(.horizontal, cheio ? 0 : 16)
                .padding(.vertical, 12)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }

    private func pilula(_ texto: String, destaque: Bool = false, icone: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icone { Image(systemName: icone).font(.system(size: 10)).foregroundStyle(Color(hex: 0x1F9E4F)) }
            Text(texto)
        }
        .font(Theme.body(12.5, weight: destaque ? .semibold : .regular))
        .foregroundStyle(destaque ? Theme.primary : Theme.textPrimary)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(destaque ? Theme.primarySoft : Color(hex: 0xF1EDE4), in: Capsule())
    }

    // MARK: Números do mês

    private func numeros(_ status: VitrineStatus) -> some View {
        let vis = status.mes?.visualizacoes ?? 0
        let cli = status.mes?.cliquesWhatsapp ?? 0
        let taxa = vis > 0 ? Int((Double(cli) / Double(vis) * 100).rounded()) : nil
        let mes = Date().formatted(.dateTime.month(.wide).locale(Locale(identifier: "pt_BR")))
        return VStack(alignment: .leading, spacing: 10) {
            Text("RETORNO EM \(mes.uppercased())")
                .font(Theme.body(11, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.textSecondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                numero("eye", Color(hex: 0x3E637F), "\(vis)", "Viram seu perfil", nil)
                numero("phone.fill", Color(hex: 0x1F9E4F), "\(cli)", "Chamaram no WhatsApp", nil)
                numero("checkmark", Theme.primary, taxa.map { "\($0)%" } ?? "—", "Viram e chamaram",
                       taxa != nil ? "de quem viu, chamou" : "aparece com as primeiras visitas")
                numero("sparkle.magnifyingglass", Color(hex: 0x7E5FC0), "\(status.impressoesTotais ?? 0)", "Aparições na busca", "desde o começo")
            }
        }
    }

    private func numero(_ icone: String, _ cor: Color, _ valor: String, _ rotulo: String, _ legenda: String?) -> some View {
        ThemeCard(padding: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icone)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(cor)
                    .frame(width: 32, height: 32)
                    .background(cor.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                Text(valor)
                    .font(Theme.moneyDisplay(26))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 6)
                Text(rotulo)
                    .font(Theme.body(12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let legenda {
                    Text(legenda)
                        .font(Theme.body(10.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Conteúdo do perfil

    private func bloco<C: View>(_ titulo: String, @ViewBuilder _ conteudo: @escaping () -> C) -> some View {
        ThemeCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(titulo)
                        .font(Theme.serifTitle(18))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    NavigationLink {
                        VitrineProfileView()
                    } label: {
                        Text("Editar")
                            .font(Theme.body(12.5, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                    }
                }
                conteudo()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sobreVoce(_ p: VitrineProfile) -> some View {
        bloco("Sobre você") {
            if let bio = p.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                Text(bio)
                    .font(Theme.body(14.5))
                    .foregroundStyle(Theme.textPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Você ainda não escreveu sua apresentação. É a primeira coisa que o paciente lê.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func comoAtende(_ p: VitrineProfile) -> some View {
        let abordagens = (p.approaches ?? []) + (p.approachOther.map { [$0] } ?? [])
        let idiomas = (p.languages ?? "").split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return bloco("Como você atende") {
            VStack(alignment: .leading, spacing: 16) {
                etiquetas("Especialidades", p.specialties, destaque: true)
                etiquetas("Abordagens", abordagens)
                etiquetas("Público atendido", p.targetAudience)
                etiquetas("Turnos", p.shifts)
                etiquetas("Modalidade", p.modalities)
                etiquetas("Idiomas", idiomas)
            }
        }
    }

    private func etiquetas(_ titulo: String, _ itens: [String]?, destaque: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(titulo.uppercased())
                .font(Theme.body(10.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
            if let itens, !itens.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(itens, id: \.self) { i in
                        Text(legivel(i))
                            .font(Theme.body(12.5, weight: destaque ? .medium : .regular))
                            .foregroundStyle(destaque ? Theme.primary : Theme.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(destaque ? Theme.primarySoft : Theme.background, in: Capsule())
                            .overlay(Capsule().stroke(destaque ? .clear : Theme.border, lineWidth: 1))
                    }
                }
            } else {
                Text("Não informado")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: Completude

    private func itensDoPerfil(_ p: VitrineProfile) -> [(String, Bool)] {
        [
            ("Foto", p.photoUrl?.isEmpty == false),
            ("Apresentação (Sobre você)", (p.bio?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0) >= 80),
            ("Especialidades", !(p.specialties ?? []).isEmpty),
            ("Abordagem", !(p.approaches ?? []).isEmpty || (p.approachOther?.isEmpty == false)),
            ("Público atendido", !(p.targetAudience ?? []).isEmpty),
            ("Modalidade", !(p.modalities ?? []).isEmpty),
            ("Turnos", !(p.shifts ?? []).isEmpty),
            ("Cidade e estado", p.city?.isEmpty == false && p.state?.isEmpty == false),
            ("WhatsApp", p.whatsapp?.isEmpty == false),
            ("Valor da consulta", (p.consultationPrice ?? 0) > 0),
        ]
    }

    private func completude(_ p: VitrineProfile) -> some View {
        let itens = itensDoPerfil(p)
        let pct = Int((Double(itens.filter(\.1).count) / Double(itens.count) * 100).rounded())
        let cor = pct == 100 ? Theme.success : pct >= 70 ? Theme.primary : Theme.warning
        return ThemeCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(Theme.border, lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: CGFloat(pct) / 100)
                            .stroke(cor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.6), value: pct)
                        Text("\(pct)%")
                            .font(Theme.body(15, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .frame(width: 70, height: 70)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(pct == 100 ? "Perfil completo" : "Complete seu perfil")
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(pct == 100
                             ? "Tudo preenchido. Você aparece do melhor jeito na busca."
                             : "Perfis completos passam mais confiança e aparecem melhor na busca.")
                            .font(Theme.body(12.5))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(itens, id: \.0) { item in
                        HStack(spacing: 9) {
                            ZStack {
                                if item.1 {
                                    Circle().fill(Theme.success)
                                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                } else {
                                    Circle().stroke(Theme.border, lineWidth: 2)
                                }
                            }
                            .frame(width: 18, height: 18)
                            Text(item.0)
                                .font(Theme.body(13))
                                .foregroundStyle(item.1 ? Theme.textSecondary : Theme.textPrimary)
                                .strikethrough(item.1, color: Theme.border)
                        }
                    }
                }
                if pct < 100 {
                    NavigationLink {
                        VitrineProfileView()
                    } label: {
                        Label("Completar agora", systemImage: "arrow.right")
                            .font(Theme.body(14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.primary, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    // MARK: Seu link

    private func seuLink(_ link: URL, nome: String) -> some View {
        let primeiro = nome.split(separator: " ").first.map(String.init)
        let convite = "Olá! Conheça meu trabalho\(primeiro.map { ", \($0)" } ?? "") na Terapia Acolher: \(link.absoluteString)"
        return VStack(alignment: .leading, spacing: 8) {
            Label("SEU LINK", systemImage: "link")
                .font(Theme.body(11, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.6))
            Text(link.absoluteString.replacingOccurrences(of: "https://", with: ""))
                .font(Theme.body(13.5, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("Coloque na bio do Instagram, no cartão de visita ou mande para quem pedir indicação.")
                .font(Theme.body(12))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = link.absoluteString
                    Haptics.success()
                    linkCopiado = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        linkCopiado = false
                    }
                } label: {
                    Label(linkCopiado ? "Copiado" : "Copiar link", systemImage: linkCopiado ? "checkmark" : "doc.on.doc")
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.pressable)
                ShareLink(item: convite) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Compartilhar meu link")
            }
            .padding(.top, 6)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    /// Opção da Vitrine como texto de gente: códigos conhecidos traduzidos, o resto com inicial maiúscula.
    private func legivel(_ valor: String) -> String {
        let rotulos = [
            "manha": "Manhã", "tarde": "Tarde", "noite": "Noite", "online": "Online",
            "presencial": "Presencial", "hibrido": "Híbrido", "feminino": "Feminino", "masculino": "Masculino",
        ]
        let v = valor.trimmingCharacters(in: .whitespaces)
        return rotulos[v.lowercased()] ?? (v.prefix(1).uppercased() + v.dropFirst())
    }
}
