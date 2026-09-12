import SwiftUI

// MARK: - Saque automático
//
// Todo dia às 18h o saldo vai sozinho pra chave escolhida, se passar do
// mínimo. Ligar exige uma chave verificada — sem chave, o backend recusa
// (400) e a tela oferece o cadastro em vez de deixar o toggle "ligado".

@MainActor
@Observable
final class FinGatewayAutoWithdrawModel {
    var chaves: [GwPixKey] = []
    var isLoading = false
    var isSaving = false
    var errorMessage: String?
    var sucesso: String?

    var enabled = false
    var usarMinimo = false
    var minimoTexto = ""
    var chaveId: String?

    private var original: GwAutoWithdraw = .desligado

    var minimo: Double? { usarMinimo ? GwMask.amount(minimoTexto) : nil }

    var chaveEscolhida: GwPixKey? {
        chaves.first { $0.id == chaveId } ?? chaves.first { $0.isDefault } ?? chaves.first
    }

    var mudou: Bool {
        enabled != original.enabled
            || (enabled && (minimo != original.minAmount || chaveEscolhida?.id != original.pixKeyId))
    }

    func podeSalvar(minimoDaConta: Double) -> Bool {
        guard mudou else { return false }
        guard enabled else { return true }
        guard chaveEscolhida != nil else { return false }
        if usarMinimo {
            guard let minimo, minimo >= minimoDaConta else { return false }
        }
        return true
    }

    func carregar(atual: GwAutoWithdraw) async {
        original = atual
        enabled = atual.enabled
        usarMinimo = atual.minAmount != nil
        minimoTexto = atual.minAmount.map { GwFormat.amountText($0) } ?? ""
        chaveId = atual.pixKeyId
        if chaves.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            chaves = try await FinGatewayAPI.pixKeys()
        } catch is CancellationError {
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível carregar as chaves."
        }
    }

    func salvar() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let body = GwAutoWithdrawBody(
                enabled: enabled,
                minAmount: enabled ? minimo : nil,
                pixKeyId: enabled ? chaveEscolhida?.id : nil
            )
            let salvo = try await FinGatewayAPI.updateAutoWithdraw(body)
            original = salvo
            enabled = salvo.enabled
            usarMinimo = salvo.minAmount != nil
            minimoTexto = salvo.minAmount.map { GwFormat.amountText($0) } ?? ""
            chaveId = salvo.pixKeyId
            Haptics.success()
            sucesso = salvo.enabled
                ? "Saque automático ligado. \(salvo.scheduleLabel)."
                : "Saque automático desligado."
            await FinGatewayStore.shared.load(showSpinner: false)
        } catch is CancellationError {
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível salvar."
            Haptics.warning()
        }
    }
}

struct FinGatewayAutoWithdrawView: View {
    @State private var model = FinGatewayAutoWithdrawModel()
    @State private var store = FinGatewayStore.shared

    private var minimoDaConta: Double { store.overview?.fees.minWithdrawal ?? 1 }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    explicacao
                    configuracao
                    if let provider = store.overview?.provider {
                        GwProviderFooter(provider: provider)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .setToolbarTitle("Saque automático")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.carregar(atual: store.account?.autoWithdraw ?? .desligado) }
        .alert("Pronto", isPresented: .init(
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

    private var explicacao: some View {
        ThemeCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 34, height: 34)
                    .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text("O saldo vai sozinho pra sua conta")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Todo dia às 18h, se o saldo passar do mínimo que você escolher, o valor é enviado por Pix pra chave escolhida. Sem tarifa de saque.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var configuracao: some View {
        PatientFormSection(icon: "gearshape", title: "CONFIGURAÇÃO") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $model.enabled) {
                    Text("Sacar automaticamente")
                        .font(Theme.body(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.primary)
                .accessibilityIdentifier("gwAutoToggle")

                if model.enabled {
                    if model.isLoading, model.chaves.isEmpty {
                        SkeletonList(linhas: 2, avatarSize: 30)
                    } else if model.chaves.isEmpty {
                        semChave
                    } else {
                        escolhaDeChave
                    }

                    Divider().overlay(Theme.border)

                    Toggle(isOn: $model.usarMinimo) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Só quando o saldo passar de um valor")
                                .font(Theme.body(14, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Desligado, saca qualquer saldo acima de \(Formatters.brl(minimoDaConta)).")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .tint(Theme.primary)

                    if model.usarMinimo {
                        GwField(label: "Saldo mínimo", hint: "A partir de \(Formatters.brl(minimoDaConta)).") {
                            TextField("0,00", text: $model.minimoTexto)
                                .keyboardType(.decimalPad)
                                .font(Theme.money(18, weight: .bold))
                                .accessibilityIdentifier("gwAutoMinimo")
                        }
                    }
                }

                PrimaryButton(
                    title: "Salvar",
                    icon: "checkmark",
                    isLoading: model.isSaving,
                    isEnabled: model.podeSalvar(minimoDaConta: minimoDaConta)
                ) {
                    Task { await model.salvar() }
                }
                .accessibilityIdentifier("gwAutoSalvar")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.enabled)
        .animation(.easeInOut(duration: 0.2), value: model.usarMinimo)
    }

    private var semChave: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cadastre uma chave Pix antes de ligar o saque automático.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
            NavigationLink {
                FinGatewayPixKeysView()
            } label: {
                Label("Cadastrar chave Pix", systemImage: "key")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.primary)
            }
            .buttonStyle(.pressable)
        }
    }

    private var escolhaDeChave: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHAVE DE DESTINO")
                .font(Theme.body(10, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Theme.textSecondary)
            ForEach(model.chaves) { chave in
                GwPixKeyOption(chave: chave, isSelected: model.chaveEscolhida?.id == chave.id) {
                    model.chaveId = chave.id
                }
            }
        }
    }
}

// MARK: - Opção de chave (saque e saque automático)

struct GwPixKeyOption: View {
    let chave: GwPixKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Theme.primary : Theme.border)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(chave.title)
                            .font(Theme.body(14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if chave.isDefault {
                            StatusBadge(label: "PADRÃO", color: Theme.warning, background: Theme.warningSoft)
                        }
                    }
                    Text("\(chave.keyType.label) · \(chave.display)")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Theme.primary : Theme.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.pressableSubtle)
    }
}
