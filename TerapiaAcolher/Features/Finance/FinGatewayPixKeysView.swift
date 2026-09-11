import SwiftUI

// MARK: - Chaves Pix do terapeuta (destino dos saques)

@MainActor
@Observable
final class FinGatewayPixKeysModel {
    var keys: [GwPixKey] = []
    var isLoading = false
    var isSaving = false
    var removingId: String?
    var errorMessage: String?

    var novoTipo: GwPixKeyType = .cpf
    var novaChave = ""
    var novoRotulo = ""

    var podeSalvar: Bool {
        switch novoTipo {
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
            _ = try await FinGatewayAPI.addPixKey(body)
            novaChave = ""
            novoRotulo = ""
            Haptics.success()
            await carregar()
        } catch is CancellationError {
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível salvar a chave."
            Haptics.warning()
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
        .alert("Ops", isPresented: .init(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var lista: some View {
        if model.isLoading, model.keys.isEmpty {
            SkeletonList(linhas: 3, avatarSize: 34)
        } else if model.keys.isEmpty {
            EmptyStateView(
                icon: "key",
                title: "Nenhuma chave salva",
                message: "Cadastre a chave Pix em que você quer receber os saques."
            )
        } else {
            ThemeCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(model.keys) { chave in
                        HStack(spacing: 12) {
                            Image(systemName: "key")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.primary)
                                .frame(width: 32, height: 32)
                                .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chave.display)
                                    .font(Theme.body(14, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Text(chave.label.map { "\(chave.keyType.label) · \($0)" } ?? chave.keyType.label)
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer(minLength: 8)
                            AsyncIconButton(
                                icon: "trash",
                                isLoading: model.removingId == chave.id,
                                isEnabled: model.removingId == nil,
                                tint: Theme.danger
                            ) {
                                removendo = chave
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        if chave.id != model.keys.last?.id {
                            Divider().overlay(Theme.border).padding(.leading, 58)
                        }
                    }
                }
            }
        }
    }

    private var formulario: some View {
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
                GwField(label: "Chave") {
                    TextField(model.novoTipo.placeholder, text: $model.novaChave)
                        .keyboardType(teclado)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("gwNovaChave")
                        .onChange(of: model.novaChave) { _, _ in model.aplicarMascara() }
                }
                GwField(label: "Apelido", hint: "Opcional — ajuda a reconhecer a chave.") {
                    TextField("Conta principal", text: $model.novoRotulo)
                        .accessibilityIdentifier("gwRotuloChave")
                }
                PrimaryButton(
                    title: "Salvar chave",
                    icon: "checkmark",
                    isLoading: model.isSaving,
                    isEnabled: model.podeSalvar
                ) {
                    Task { await model.adicionar() }
                }
                .accessibilityIdentifier("gwSalvarChave")
            }
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
