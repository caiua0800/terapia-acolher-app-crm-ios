import SwiftUI
import UserNotifications

/// Convite para ligar as notificações.
///
/// Não é o alerta do sistema — é uma tela nossa que aparece ANTES dele. A
/// diferença importa: o alerta do iOS só pode ser mostrado **uma vez**. Se o
/// terapeuta negar ali, o app nunca mais consegue pedir, e ele passa a depender
/// de achar o caminho nos Ajustes do iPhone.
///
/// Perguntando antes, "Agora não" custa nada: o alerta do sistema segue
/// intacto, e a gente pode convidar de novo mais adiante.
struct PushOptInSheet: View {
    var onDecidiu: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pedindo = false

    private static let motivos: [(icone: String, titulo: String, texto: String)] = [
        ("calendar", "Sessão em 1 hora", "Um lembrete antes de cada atendimento."),
        ("checkmark.circle", "Pagamento confirmado", "Você sabe na hora que o paciente pagou."),
        ("person.badge.plus", "Novo paciente chegou", "Não perde um contato por não ter visto."),
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 12)

                Image(systemName: "bell.badge")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 78, height: 78)
                    .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 22))

                Text("Quer ser avisada?")
                    .font(Theme.serifTitle(25))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 18)

                Text("Sem isso, você só descobre o que aconteceu quando abre o app.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .padding(.horizontal, 8)

                VStack(spacing: 14) {
                    ForEach(Self.motivos, id: \.titulo) { motivo in
                        HStack(spacing: 13) {
                            Image(systemName: motivo.icone)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.primary)
                                .frame(width: 36, height: 36)
                                .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(motivo.titulo)
                                    .font(Theme.body(15, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(motivo.texto)
                                    .font(Theme.body(13))
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.top, 26)
                .padding(.horizontal, 4)

                Spacer(minLength: 20)

                PrimaryButton(
                    title: "Ativar notificações",
                    icon: "bell",
                    isLoading: pedindo
                ) {
                    Task {
                        pedindo = true
                        _ = await PushManager.shared.requestAuthorization()
                        pedindo = false
                        fechar()
                    }
                }

                Button {
                    Haptics.tap()
                    fechar()
                } label: {
                    Text("Agora não")
                        .font(Theme.body(15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.pressable)
                .disabled(pedindo)

                Text("Dá pra mudar isso quando quiser, em Configurações.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 16)
        }
        .interactiveDismissDisabled(pedindo)
    }

    private func fechar() {
        onDecidiu()
        dismiss()
    }
}

/// Decide quando convidar.
///
/// Regras, em ordem de importância:
/// 1. Nunca antes de o terapeuta ter usado o app. Pedir na primeira tela é o
///    jeito mais rápido de levar um "não" definitivo do sistema.
/// 2. "Agora não" adia por uma semana, não para sempre — mas a cada recusa o
///    intervalo dobra, até parar de perguntar. Insistir irrita e não converte.
/// 3. Se o sistema já foi respondido (autorizado ou negado), nunca mais mostra:
///    o alerta do iOS não pode ser reapresentado, então a nossa tela não teria
///    o que fazer.
@Observable
@MainActor
final class PushOptIn {
    static let shared = PushOptIn()

    private let defaults = UserDefaults.standard
    private let chaveAdiadoAte = "push.optin.adiadoAte"
    private let chaveRecusas = "push.optin.recusas"
    private let chaveAberturas = "push.optin.aberturas"

    /// Aberturas antes do primeiro convite. O terapeuta precisa ter visto o app
    /// funcionando para a pergunta fazer sentido.
    private let aberturasMinimas = 2
    /// Depois de 3 "agora não", paramos: quem recusou três vezes está dizendo
    /// não, e o caminho passa a ser Configurações.
    private let recusasMaximas = 3

    var mostrando = false

    func registrarAbertura() {
        defaults.set(defaults.integer(forKey: chaveAberturas) + 1, forKey: chaveAberturas)
    }

    func avaliar(status: UNAuthorizationStatus?) {
        guard status == .notDetermined else { return }
        guard defaults.integer(forKey: chaveAberturas) >= aberturasMinimas else { return }
        guard defaults.integer(forKey: chaveRecusas) < recusasMaximas else { return }
        if let ate = defaults.object(forKey: chaveAdiadoAte) as? Date, ate > Date() { return }
        mostrando = true
    }

    /// Chamado quando a tela fecha, tendo o terapeuta ativado ou não. Se ele
    /// ativou, o status deixa de ser `notDetermined` e `avaliar` nunca mais
    /// libera — então não é preciso distinguir aqui.
    func registrarDecisao() {
        let recusas = defaults.integer(forKey: chaveRecusas) + 1
        defaults.set(recusas, forKey: chaveRecusas)
        let dias = 7 * NSDecimalNumber(decimal: pow(2, recusas - 1)).intValue
        defaults.set(
            Calendar.current.date(byAdding: .day, value: dias, to: Date()),
            forKey: chaveAdiadoAte
        )
    }
}
