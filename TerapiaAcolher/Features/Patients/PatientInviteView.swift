import Observation
import SwiftUI

// MARK: - API

enum InviteKind: String, CaseIterable, Identifiable {
    case registration = "REGISTRATION"
    case registrationAndAnamnesis = "REGISTRATION_AND_ANAMNESIS"
    case anamnesis = "ANAMNESIS"

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .registration: "Só o cadastro"
        case .registrationAndAnamnesis: "Cadastro e anamnese"
        case .anamnesis: "Só a anamnese"
        }
    }

    var descricao: String {
        switch self {
        case .registration: "O paciente preenche os próprios dados."
        case .registrationAndAnamnesis: "Ele se cadastra e já responde a anamnese."
        case .anamnesis: "Para um paciente que já está na sua lista."
        }
    }

    var precisaPaciente: Bool { self == .anamnesis }
    var precisaModelo: Bool { self != .registration }
}

struct InviteResult: Decodable {
    let id: String
    let url: String
    let expiresAt: Date
}

@Observable
@MainActor
final class PatientInviteViewModel {
    var kind: InviteKind = .registrationAndAnamnesis
    var paciente: Patient?
    var modelo: RecTemplate?
    var modelos: [RecTemplate] = []
    var pacientes: [Patient] = []

    var gerando = false
    var resultado: InviteResult?
    var erro: String?
    var mostrarErro = false

    var podeGerar: Bool {
        if gerando { return false }
        if kind.precisaPaciente && paciente == nil { return false }
        if kind.precisaModelo && modelo == nil { return false }
        return true
    }

    func carregar() async {
        async let m = RecordsAPI.templates(kind: .anamnesis)
        async let p = PatientsAPI.list(status: "ACTIVE", groupId: nil, search: "")
        modelos = (try? await m) ?? []
        pacientes = (try? await p) ?? []
        // Pré-seleciona o primeiro modelo: quase sempre é o que ele quer, e
        // reduz o formulário a uma decisão só.
        if modelo == nil { modelo = modelos.first }
    }

    func gerar() async {
        gerando = true
        defer { gerando = false }
        struct Body: Encodable {
            let kind: String
            let patientId: String?
            let templateId: String?
        }
        do {
            resultado = try await APIClient.shared.post(
                "patient-invites",
                body: Body(
                    kind: kind.rawValue,
                    patientId: kind.precisaPaciente ? paciente?.id : nil,
                    templateId: kind.precisaModelo ? modelo?.id : nil
                )
            )
            Haptics.success()
        } catch let e as APIError {
            erro = e.message
            mostrarErro = true
        } catch {
            erro = "Não foi possível gerar o link."
            mostrarErro = true
        }
    }
}

/// Gera o link que o terapeuta manda ao paciente pelo WhatsApp.
///
/// O link é a única credencial de quem abrir — por isso ele aparece UMA vez,
/// aqui, e depois só existe cifrado no servidor. A tela deixa isso explícito
/// em vez de o terapeuta descobrir quando voltar e não achar mais.
struct PatientInviteView: View {
    @State private var model = PatientInviteViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let r = model.resultado {
                            PatientInviteLinkCard(result: r, kind: model.kind)
                        } else {
                            formulario
                        }
                    }
                    .padding(Theme.screenPadding)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Convidar paciente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(model.resultado == nil ? "Cancelar" : "Concluir") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            .task { await model.carregar() }
            .alert("Ops", isPresented: $model.mostrarErro) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.erro ?? "Algo deu errado.")
            }
        }
    }

    @ViewBuilder
    private var formulario: some View {
        Text("Mande um link para o paciente preencher no celular dele. Vale por 7 dias e só pode ser usado uma vez.")
            .font(Theme.body(14))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

        VStack(alignment: .leading, spacing: 8) {
            Text("O QUE ELE VAI PREENCHER")
                .font(Theme.body(10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)

            ThemeCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(InviteKind.allCases.enumerated()), id: \.element.id) { i, k in
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { model.kind = k }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(k.titulo)
                                        .font(Theme.body(15, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(k.descricao)
                                        .font(Theme.body(12))
                                        .foregroundStyle(Theme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: model.kind == k ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(model.kind == k ? Theme.primary : Theme.border)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressableSubtle)
                        if i < InviteKind.allCases.count - 1 {
                            Divider().overlay(Theme.border)
                        }
                    }
                }
            }
        }

        if model.kind.precisaPaciente {
            escolha(
                titulo: "DE QUEM É A ANAMNESE",
                atual: model.paciente?.name ?? "Escolher paciente",
                vazio: model.paciente == nil
            ) {
                ForEach(model.pacientes) { p in
                    Button(p.name) { model.paciente = p }
                }
            }
        }

        if model.kind.precisaModelo {
            escolha(
                titulo: "MODELO DE ANAMNESE",
                atual: model.modelo?.name ?? "Escolher modelo",
                vazio: model.modelo == nil
            ) {
                ForEach(model.modelos) { t in
                    Button(t.name) { model.modelo = t }
                }
            }
        }

        PrimaryButton(
            title: "Gerar link",
            icon: "link",
            isLoading: model.gerando
        ) {
            Task { await model.gerar() }
        }
        .disabled(!model.podeGerar)
        .opacity(model.podeGerar ? 1 : 0.5)
    }

    private func escolha<C: View>(
        titulo: String,
        atual: String,
        vazio: Bool,
        @ViewBuilder opcoes: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titulo)
                .font(Theme.body(10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
            Menu {
                opcoes()
            } label: {
                HStack {
                    Text(atual)
                        .font(Theme.body(15, weight: vazio ? .regular : .semibold))
                        .foregroundStyle(vazio ? Theme.textSecondary : Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1)
                )
            }
        }
    }
}

/// Link pronto, com a mensagem já escrita para o WhatsApp.
private struct PatientInviteLinkCard: View {
    let result: InviteResult
    let kind: InviteKind

    @State private var copiado: String?
    @Environment(\.openURL) private var openURL

    private var mensagem: String {
        let oQue = kind == .registration
            ? "seu cadastro"
            : kind == .anamnesis
                ? "algumas perguntas antes da nossa sessão"
                : "seu cadastro e algumas perguntas antes da nossa sessão"
        return """
        Oi! Para adiantar nosso atendimento, preenche \(oQue) por aqui, por favor:

        \(result.url)

        O link vale por 7 dias. Qualquer dúvida é só me chamar.
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.success)
                    .frame(width: 34, height: 34)
                    .background(Theme.successSoft, in: Circle())
                Text("Link criado")
                    .font(Theme.serifTitle(20))
                    .foregroundStyle(Theme.textPrimary)
            }

            ThemeCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("LINK")
                        .font(Theme.body(10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.textSecondary)
                    Text(result.url)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            PrimaryButton(
                title: copiado == "msg" ? "Mensagem copiada!" : "Copiar mensagem pro WhatsApp",
                icon: copiado == "msg" ? "checkmark" : "text.bubble"
            ) {
                copiar(mensagem, "msg")
            }

            Button {
                copiar(result.url, "link")
            } label: {
                Label(
                    copiado == "link" ? "Link copiado" : "Copiar só o link",
                    systemImage: copiado == "link" ? "checkmark" : "link"
                )
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.pressable)

            // O link não é recuperável depois. Melhor avisar aqui do que ele
            // voltar procurando e não achar.
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Text("Copie agora: por segurança, este link não fica guardado e não dá para vê-lo de novo. Se perder, gere outro.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func copiar(_ texto: String, _ tipo: String) {
        UIPasteboard.general.string = texto
        Haptics.success()
        withAnimation { copiado = tipo }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if copiado == tipo { withAnimation { copiado = nil } }
        }
    }
}
