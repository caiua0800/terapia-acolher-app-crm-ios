import Observation
import SwiftUI

/// Meu consultório — nome, endereço e duração padrão da sessão.
/// GET/PUT settings/office.
struct SetOfficeView: View {
    @State private var viewModel = SetOfficeViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if viewModel.isLoading {
                ProgressView().tint(Theme.primary)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 8) {
                            SetSectionHeader(title: "Identificação")
                            ThemeCard {
                                VStack(alignment: .leading, spacing: 16) {
                                    campo("Nome do consultório") {
                                        TextField("Ex.: Consultório Acolher", text: $viewModel.officeName)
                                    }
                                    Divider()
                                    campo("Endereço") {
                                        TextField(
                                            "Rua, número, sala, cidade/UF",
                                            text: $viewModel.address,
                                            axis: .vertical
                                        )
                                        .lineLimit(2 ... 4)
                                    }
                                }
                            }
                        }

                        VStack(spacing: 8) {
                            SetSectionHeader(title: "Sessões")
                            ThemeCard {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Duração padrão da sessão")
                                            .font(Theme.body(15, weight: .medium))
                                            .foregroundStyle(Theme.textPrimary)
                                        Text("Usada como sugestão ao criar sessões")
                                            .font(Theme.body(12))
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    Stepper(
                                        value: $viewModel.defaultSessionMinutes,
                                        in: 10 ... 480,
                                        step: 5
                                    ) {
                                        Text("\(viewModel.defaultSessionMinutes) min")
                                            .font(Theme.money(16))
                                            .foregroundStyle(Theme.textPrimary)
                                    }
                                    .fixedSize()
                                }
                            }
                        }

                        PrimaryButton(title: "Salvar", isLoading: viewModel.isSaving) {
                            Task {
                                if await viewModel.save() { dismiss() }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.vertical, 16)
                }
            }
        }
        .setToolbarTitle("Meu consultório")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .alert("Ops", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Algo deu errado.")
        }
    }

    private func campo(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(Theme.body(11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .tracking(0.8)
            content()
                .font(Theme.body(15))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

@Observable
final class SetOfficeViewModel {
    var officeName = ""
    var address = ""
    var defaultSessionMinutes = 50
    var isLoading = true
    var isSaving = false
    var errorMessage: String?
    var showError = false

    @MainActor
    func load() async {
        defer { isLoading = false }
        do {
            let office: SetOffice = try await APIClient.shared.get("settings/office")
            officeName = office.officeName ?? ""
            address = office.address ?? ""
            defaultSessionMinutes = office.defaultSessionMinutes
        } catch {
            present(error)
        }
    }

    @MainActor
    func save() async -> Bool {
        struct Body: Encodable {
            let officeName: String
            let address: String
            let defaultSessionMinutes: Int
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let _: SetOffice = try await APIClient.shared.put(
                "settings/office",
                body: Body(
                    officeName: officeName.trimmingCharacters(in: .whitespacesAndNewlines),
                    address: address.trimmingCharacters(in: .whitespacesAndNewlines),
                    defaultSessionMinutes: defaultSessionMinutes
                )
            )
            return true
        } catch {
            present(error)
            return false
        }
    }

    @MainActor
    private func present(_ error: Error) {
        errorMessage = (error as? APIError)?.message ?? "Não foi possível concluir. Verifique sua conexão."
        showError = true
    }
}
