import SwiftUI

// MARK: - Chaves Pix do terapeuta (destino dos saques)
//
// Regra do produto (2026-09-12): o saque só vai pra uma conta do próprio
// terapeuta. O backend consulta a titularidade da chave e recusa (422) o que
// não estiver no CPF/CNPJ da conta — a mensagem chega pronta e é mostrada
// como veio. Uma chave é a padrão (pré-selecionada no saque); no máximo 5.

@MainActor
@Observable
final class FinGatewayPixKeysModel {
    static let limite = 5

    var keys: [GwPixKey] = []
    var isLoading = false
    var isSaving = false
    var removingId: String?
    var definindoPadraoId: String?
    var errorMessage: String?
    var sucesso: String?

    var novoTipo: GwPixKeyType = .cpf
    var novaChave = ""
    var novoRotulo = ""

    var atingiuLimite: Bool { keys.count >= Self.limite }

    var podeSalvar: Bool {
        guard !atingiuLimite else { return false }
        return switch novoTipo {
        case .cpf: GwMask.digits(novaChave).count == 11
        case .cnpj: GwMask.digits(novaChave).count == 14
        case .phone: GwMask.digits(novaChave).count >= 10
        case .email: novaChave.contains("@") && novaChave.contains(".")
        case .evp: novaChave.trimmingCharacters(in: .whitespaces).count == 36
        }
    }

    func carregar() async {
        if keys.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            keys = try await FinGatewayAPI.pixKeys()
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível carregar as chaves."
        }
    }

    func adicionar() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let body = GwPixKeyBody(
                keyType: novoTipo.rawValue,
                key: novaChave.trimmingCharacters(in: .whitespaces),
                label: novoRotulo.isEmpty ? nil : novoRotulo
            )
            let chave = try await FinGatewayAPI.addPixKey(body)
            novaChave = ""
            novoRotulo = ""
            Haptics.success()
            sucesso = "Chave \(chave.keyType.label) verificada: está no seu nome\(chave.ownerName.map { " (\($0))" } ?? "")."
            await carregar()
        } catch is CancellationError {
        } catch {
            // 422 = chave de terceiro; 409 = repetida; 400 = limite. A frase do
            // backend já explica — não reescrever.
            errorMessage = (error as? APIError)?.message ?? "Não foi possível salvar a chave."
            Haptics.warning()
        }
    }

    func definirPadrao(_ chave: GwPixKey) async {
        guard !chave.isDefault else { return }
        definindoPadraoId = chave.id
        defer { definindoPadraoId = nil }
        do {
            keys = try await FinGatewayAPI.setDefaultPixKey(id: chave.id)
            Haptics.success()
        } catch is CancellationError {
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível definir a chave padrão."
        }
    }

    func remover(_ chave: GwPixKey) async {
        removingId = chave.id
        defer { removingId = nil }
        do {
            _ = try await FinGatewayAPI.removePixKey(id: chave.id)
            await carregar()
        } catch is CancellationError {
        } catch {
            // 400 quando é a chave do saque automático — a mensagem vem pronta.
            errorMessage = (error as? APIError)?.message ?? "Não foi possível remover a chave."
        }
    }

    /// Máscara conforme o tipo escolhido.
    func aplicarMascara() {
        let mascarada: String = switch novoTipo {
        case .cpf: GwMask.cpf(novaChave)
        case .cnpj: GwMask.cnpj(novaChave)
        case .phone: GwMask.phone(novaChave)
        case .email, .evp: novaChave
        }
        if mascarada != novaChave { novaChave = mascarada }
    }
}

struct FinGatewayPixKeysView: View {
    @State private var model = FinGatewayPixKeysModel()
    @State private var store = FinGatewayStore.shared
    @State private var removendo: GwPixKey?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    regra
                    lista
                    formulario
                    if let provider = store.overview?.provider {
                        GwProviderFooter(provider: provider)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .refreshable { await model.carregar() }
        }
        .setToolbarTitle("Chaves Pix")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.carregar() }
        .alert("Remover chave?", isPresented: .init(
            get: { removendo != nil },
            set: { if !$0 { removendo = nil } }
        )) {
            Button("Remover", role: .destructive) {
                if let chave = removendo {
                    Task { await model.remover(chave) }
                }
            }
            Button("Voltar", role: .cancel) {}
        } message: {
            Text("A chave sai da lista de destinos de saque. Você pode cadastrar de novo depois.")
        }
        .alert("Chave verificada", isPresented: .init(
            get: { model.sucesso != nil },
            set: { if !$0 { model.sucesso = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.sucesso ?? "")
        }
        .alert("Ops", isPresented: .init(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: Regra, dita uma vez e curta

    private var regra: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.badge.shield.checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Só chaves no seu CPF/CNPJ")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("O saque vai sempre pra uma conta sua. A titularidade é conferida na hora do cadastro.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.primarySoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Lista

    @ViewBuilder
    private var lista: some View {
        if model.isLoading, model.keys.isEmpty {
            SkeletonList(linhas: 3, avatarSize: 34)
        } else if model.keys.isEmpty {
            EmptyStateView(
                icon: "key",
                title: "Nenhuma chave salva",
                message: "Cadastre a chave Pix, no seu nome, em que você quer receber os saques."
            )
        } else {
            ThemeCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(model.keys) { chave in
                        linha(chave)
                        if chave.id != model.keys.last?.id {
                            Divider().overlay(Theme.border).padding(.leading, 58)
                        }
                    }
                }
            }
        }
    }

    private func linha(_ chave: GwPixKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: chave.isDefault ? "star.fill" : "key")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(chave.isDefault ? Theme.warning : Theme.primary)
                .frame(width: 32, height: 32)
                .background(
                    chave.isDefault ? Theme.warningSoft : Theme.primarySoft,
                    in: RoundedRectangle(cornerRadius: 9)
                )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(chave.title)
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if chave.isDefault {
                        StatusBadge(label: "PADRÃO", color: Theme.warning, background: Theme.warningSoft)
                    }
                }
                Text(chave.label == nil ? chave.display : "\(chave.keyType.label) · \(chave.display)")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                if chave.verifiedAt != nil {
                    Label(
                        chave.ownerName.map { "Verificada · \($0)" } ?? "Titularidade verificada",
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(Theme.body(11, weight: .medium))
                    .foregroundStyle(Theme.success)
                    .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if !chave.isDefault {
                AsyncIconButton(
                    icon: "star",
                    isLoading: model.definindoPadraoId == chave.id,
                    isEnabled: model.definindoPadraoId == nil && model.removingId == nil,
                    tint: Theme.warning
                ) {
                    Task { await model.definirPadrao(chave) }
                }
                .accessibilityLabel("Tornar padrão")
            }
            AsyncIconButton(
                icon: "trash",
                isLoading: model.removingId == chave.id,
                isEnabled: model.removingId == nil && model.definindoPadraoId == nil,
                tint: Theme.danger
            ) {
                removendo = chave
            }
            .accessibilityLabel("Remover")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Formulário

    @ViewBuilder
    private var formulario: some View {
        if model.atingiuLimite {
            ThemeCard {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Theme.textSecondary)
                    Text("Limite de \(FinGatewayPixKeysModel.limite) chaves. Remova uma pra cadastrar outra.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                }
            }
        } else {
            PatientFormSection(icon: "plus.circle", title: "NOVA CHAVE") {
                VStack(alignment: .leading, spacing: 14) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(GwPixKeyType.allCases, id: \.self) { tipo in
                                FilterChip(label: tipo.label, isSelected: model.novoTipo == tipo) {
                                    model.novoTipo = tipo
                                    model.novaChave = ""
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    GwField(label: "Chave", hint: dicaDoTipo) {
                        TextField(model.novoTipo.placeholder, text: $model.novaChave)
                            .keyboardType(teclado)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("gwNovaChave")
                            .onChange(of: model.novaChave) { _, _ in model.aplicarMascara() }
                    }
                    GwField(label: "Apelido", hint: "Opcional — o banco onde a chave está, por exemplo.") {
                        TextField("Nubank", text: $model.novoRotulo)
                            .accessibilityIdentifier("gwRotuloChave")
                    }
                    PrimaryButton(
                        title: "Verificar e salvar",
                        icon: "checkmark.seal",
                        isLoading: model.isSaving,
                        isEnabled: model.podeSalvar
                    ) {
                        Task { await model.adicionar() }
                    }
                    .accessibilityIdentifier("gwSalvarChave")
                }
            }
        }
    }

    private var dicaDoTipo: String {
        switch model.novoTipo {
        case .cpf, .cnpj: "Precisa ser o mesmo documento da sua conta."
        case .email: "O e-mail cadastrado como chave no seu banco."
        case .phone: "O celular cadastrado como chave no seu banco."
        case .evp: "A chave aleatória gerada pelo seu banco."
        }
    }

    private var teclado: UIKeyboardType {
        switch model.novoTipo {
        case .cpf, .cnpj, .phone: .numberPad
        case .email: .emailAddress
        case .evp: .asciiCapable
        }
    }
}
