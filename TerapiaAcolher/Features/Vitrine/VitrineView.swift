import Observation
import SwiftUI

@Observable
final class VitrineViewModel {
    var status: VitrineStatus?
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
            status = try await VitrineAPI.status()
        } catch is CancellationError {
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar sua Vitrine."
        }
        isLoading = false
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
    @State private var model = VitrineViewModel()
    @State private var showDisconnect = false
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
            ThemeCard {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Theme.warning)
                    Text("Não conseguimos falar com a Vitrine agora. Seu perfil continua no ar.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            metricas(status)
            planoCard(status)
        }

        NavigationLink {
            VitrineProfileView()
        } label: {
            ThemeCard(padding: 15) {
                HStack(spacing: 12) {
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 34, height: 34)
                        .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Editar meu perfil")
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Foto, bio, especialidades e valor")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.5))
                }
            }
        }
        .buttonStyle(.pressableSubtle)

        if let slug = status.slug,
           let url = URL(string: "https://vitrine.terapiaacolher.com.br/terapeuta/\(slug)") {
            Button {
                Haptics.tap()
                openURL(url)
            } label: {
                Label("Ver meu perfil público", systemImage: "safari")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.primarySoft, in: Capsule())
            }
            .buttonStyle(.pressable)
        }

        Button(role: .destructive) {
            showDisconnect = true
        } label: {
            Text("Desconectar")
                .font(Theme.body(14, weight: .semibold))
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .disabled(model.isWorking)
        .padding(.top, 4)
    }

    private func metricas(_ status: VitrineStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ESTE MÊS")
                .font(Theme.body(11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 2)

            HStack(spacing: 10) {
                metricaTile(
                    valor: "\(status.mes?.visualizacoes ?? 0)",
                    titulo: "Viram seu perfil",
                    cor: Theme.textPrimary
                )
                metricaTile(
                    valor: "\(status.mes?.cliquesWhatsapp ?? 0)",
                    titulo: "Chamaram no WhatsApp",
                    cor: Theme.success
                )
            }

            if let total = status.impressoesTotais, total > 0 {
                Text("\(total) aparições na busca desde o começo")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 2)
            }
        }
    }

    private func metricaTile(valor: String, titulo: String, cor: Color) -> some View {
        ThemeCard(padding: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(valor)
                    .font(Theme.moneyDisplay(28))
                    .monospacedDigit()
                    .foregroundStyle(cor)
                Text(titulo)
                    .font(Theme.body(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func planoCard(_ status: VitrineStatus) -> some View {
        ThemeCard(padding: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SEU PLANO")
                        .font(Theme.body(10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.textSecondary)
                    Text(status.planoLegivel)
                        .font(Theme.body(17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let expira = status.plano?.expiraEm {
                        Text("Renova em \(PatientFormat.fullDate.string(from: expira))")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                if status.perfilAtivo == true {
                    StatusBadge(label: "NO AR", color: Theme.success, background: Theme.successSoft)
                } else {
                    StatusBadge(label: "OCULTO", color: Theme.warning, background: Theme.warningSoft)
                }
            }
        }
    }
}
