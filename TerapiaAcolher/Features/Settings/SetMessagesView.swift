import Observation
import SwiftUI

/// Configurações → Mensagens aos pacientes (WhatsApp). Padrão: tudo ligado.
struct MensagensWhatsapp: Codable, Equatable {
    var enabled: Bool
    var reminder24h: Bool
    var reminder1h: Bool
    var chargeReminder: Bool
    var chargeRetry: Bool

    static let padrao = MensagensWhatsapp(
        enabled: true, reminder24h: true, reminder1h: true, chargeReminder: true, chargeRetry: true
    )

    /// Chaves por tipo (a geral é `enabled`).
    enum Tipo: String, CaseIterable {
        case reminder24h, reminder1h, chargeReminder, chargeRetry
    }

    subscript(tipo: Tipo) -> Bool {
        get {
            switch tipo {
            case .reminder24h: reminder24h
            case .reminder1h: reminder1h
            case .chargeReminder: chargeReminder
            case .chargeRetry: chargeRetry
            }
        }
        set {
            switch tipo {
            case .reminder24h: reminder24h = newValue
            case .reminder1h: reminder1h = newValue
            case .chargeReminder: chargeReminder = newValue
            case .chargeRetry: chargeRetry = newValue
            }
        }
    }
}

enum MensagensAPI {
    static func carregar() async throws -> MensagensWhatsapp {
        try await APIClient.shared.get("settings/whatsapp-messages")
    }

    /// Manda só o campo mudado; o servidor devolve o objeto inteiro.
    static func salvar(_ campo: String, _ valor: Bool) async throws -> MensagensWhatsapp {
        try await APIClient.shared.put("settings/whatsapp-messages", body: [campo: valor])
    }
}

@Observable
final class SetMessagesViewModel {
    var dados: MensagensWhatsapp?
    var isLoading = true
    var loadError: String?
    /// Chave em voo: o spinner aparece só nela.
    var salvando: String?
    var errorMessage: String?
    var showError = false

    @MainActor
    func load() async {
        isLoading = dados == nil
        loadError = nil
        do {
            dados = try await MensagensAPI.carregar()
        } catch is CancellationError {
        } catch {
            loadError = (error as? APIError)?.message ?? "Não foi possível carregar."
        }
        isLoading = false
    }

    /// Otimista: muda na hora e volta se a API recusar.
    @MainActor
    func mudar(_ campo: String, para valor: Bool, aplicar: (inout MensagensWhatsapp) -> Void) async {
        guard var atual = dados, salvando == nil else { return }
        let anterior = atual
        aplicar(&atual)
        dados = atual
        salvando = campo
        Haptics.tap()
        do {
            dados = try await MensagensAPI.salvar(campo, valor)
            SettingsHomeViewModel.shared.messagesEnabled = dados?.enabled
        } catch {
            dados = anterior
            errorMessage = (error as? APIError)?.message ?? "Não foi possível salvar. Verifique sua conexão."
            showError = true
            Haptics.warning()
        }
        salvando = nil
    }
}

struct SetMessagesView: View {
    @State private var model = SetMessagesViewModel()

    private static let grupos: [(titulo: String, icone: String, itens: [(tipo: MensagensWhatsapp.Tipo, titulo: String, texto: String)])] = [
        ("Sessões", "calendar", [
            (.reminder24h, "Lembrete 24 horas antes", "Avisa o paciente da sessão de amanhã, com dia e horário."),
            (.reminder1h, "Aviso 1 hora antes da videochamada", "Só em sessão online: vai com o botão para entrar na chamada."),
        ]),
        ("Cobranças", "dollarsign.circle", [
            (.chargeReminder, "Aviso de cobrança", "No dia do vencimento, com o botão para pagar."),
            (.chargeRetry, "Reaviso de cobrança", "3 dias depois do vencimento, se ainda não foi paga. Uma vez só."),
        ]),
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if model.isLoading {
                ProgressView().tint(Theme.primary)
            } else if let erro = model.loadError {
                ErrorRetryView(message: erro) { Task { await model.load() } }
            } else if let dados = model.dados {
                ScrollView {
                    VStack(spacing: 20) {
                        chaveGeral(dados)
                        ForEach(Self.grupos, id: \.titulo) { grupo in
                            VStack(spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: grupo.icone).font(.system(size: 11, weight: .semibold))
                                    Text(grupo.titulo.uppercased())
                                        .font(Theme.body(11, weight: .semibold))
                                        .tracking(1.2)
                                    Spacer()
                                }
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 4)
                                ThemeCard(padding: 0) {
                                    VStack(spacing: 0) {
                                        ForEach(Array(grupo.itens.enumerated()), id: \.offset) { i, item in
                                            if i > 0 { Divider().overlay(Theme.border) }
                                            LinhaDeChave(
                                                titulo: item.titulo,
                                                texto: item.texto,
                                                ligado: dados.enabled && dados[item.tipo],
                                                travado: !dados.enabled || model.salvando != nil,
                                                salvando: model.salvando == item.tipo.rawValue
                                            ) { novo in
                                                Task {
                                                    await model.mudar(item.tipo.rawValue, para: novo) { $0[item.tipo] = novo }
                                                }
                                            }
                                        }
                                    }
                                }
                                .opacity(dados.enabled ? 1 : 0.55)
                            }
                        }
                        nota
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 16)
                    .padding(.bottom, 48)
                }
                .refreshable { await model.load() }
            }
        }
        .setToolbarTitle("Mensagens aos pacientes")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .alert("Ops", isPresented: $model.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Algo deu errado.")
        }
    }

    private func chaveGeral(_ dados: MensagensWhatsapp) -> some View {
        let geral = dados.enabled
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: "message.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(geral ? Color.white : Theme.textSecondary)
                .frame(width: 48, height: 48)
                .background(geral ? Color(hex: 0x25D366) : Color(hex: 0xF1EDE4))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(geral ? "Mensagens ligadas" : "Mensagens desligadas")
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(geral
                     ? "Seus pacientes recebem no WhatsApp a confirmação da sessão, os lembretes e as cobranças que estiverem ligados abaixo."
                     : "Nenhum paciente recebe mensagem de WhatsApp do CRM: nem confirmação, nem lembrete, nem cobrança.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            ChaveComSpinner(
                ligado: geral,
                travado: model.salvando != nil,
                salvando: model.salvando == "enabled",
                rotulo: "Enviar mensagens aos pacientes"
            ) { novo in
                Task { await model.mudar("enabled", para: novo) { $0.enabled = novo } }
            }
        }
        .padding(18)
        .background(geral ? Color(hex: 0xE3F5EA) : Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(geral ? Color.clear : Theme.border))
        .animation(.easeInOut(duration: 0.2), value: geral)
    }

    private var nota: some View {
        VStack(alignment: .leading, spacing: 8) {
            (Text("Só para um paciente? ").bold().foregroundColor(Theme.textPrimary)
             + Text("Abra a ficha dele em Pacientes e desligue lá. O que está desligado aqui aparece desligado em todas as fichas."))
            Text("O código que confirma o seu número e o aviso de pagamento recebido chegam para você, não para o paciente, e não dependem desta tela. Os e-mails de lembrete continuam seguindo a ficha do paciente.")
        }
        .font(Theme.body(12.5))
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(hex: 0xF3EFE7))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Linha com título, explicação e a chave (com spinner quando está salvando).
struct LinhaDeChave: View {
    let titulo: String
    let texto: String
    let ligado: Bool
    let travado: Bool
    let salvando: Bool
    let aoMudar: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                    .font(Theme.body(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(texto)
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            ChaveComSpinner(ligado: ligado, travado: travado, salvando: salvando, rotulo: titulo, aoMudar: aoMudar)
        }
        .padding(.horizontal, Theme.cardPadding)
        .padding(.vertical, 14)
    }
}

/// Toggle do app; em voo, o spinner aparece ao lado e a chave fica travada.
struct ChaveComSpinner: View {
    let ligado: Bool
    let travado: Bool
    let salvando: Bool
    let rotulo: String
    let aoMudar: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if salvando {
                ProgressView().controlSize(.small).tint(Theme.textSecondary)
            }
            Toggle(rotulo, isOn: Binding(get: { ligado }, set: { aoMudar($0) }))
                .labelsHidden()
                .tint(Theme.primary)
                .disabled(travado)
        }
        .animation(.easeInOut(duration: 0.15), value: salvando)
    }
}
