import Observation
import SwiftUI

/// Configurações da agenda — horários de trabalho simples
/// (dias da semana + início/fim), gravados no JSON `agenda` de settings/office.
struct SetAgendaView: View {
    @State private var viewModel = SetAgendaViewModel()
    @Environment(\.dismiss) private var dismiss

    /// (rótulo, ISO weekday) — 1 = segunda … 7 = domingo.
    private let dias: [(String, Int)] = [
        ("Seg", 1), ("Ter", 2), ("Qua", 3), ("Qui", 4), ("Sex", 5), ("Sáb", 6), ("Dom", 7),
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if viewModel.isLoading {
                ProgressView().tint(Theme.primary)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 8) {
                            SetSectionHeader(title: "Dias de atendimento")
                            ThemeCard {
                                HStack(spacing: 8) {
                                    ForEach(dias, id: \.1) { dia in
                                        diaChip(label: dia.0, weekday: dia.1)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }

                        VStack(spacing: 8) {
                            SetSectionHeader(title: "Horário de trabalho")
                            ThemeCard {
                                VStack(spacing: 12) {
                                    HStack {
                                        Text("Início")
                                            .font(Theme.body(15, weight: .medium))
                                            .foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                        DatePicker(
                                            "",
                                            selection: $viewModel.start,
                                            displayedComponents: .hourAndMinute
                                        )
                                        .labelsHidden()
                                    }
                                    Divider()
                                    HStack {
                                        Text("Fim")
                                            .font(Theme.body(15, weight: .medium))
                                            .foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                        DatePicker(
                                            "",
                                            selection: $viewModel.end,
                                            displayedComponents: .hourAndMinute
                                        )
                                        .labelsHidden()
                                    }
                                }
                            }
                        }

                        Text("Esses horários orientam a criação de sessões na agenda.")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)

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
        .setToolbarTitle("Configurações da agenda")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .alert("Ops", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Algo deu errado.")
        }
    }

    private func diaChip(label: String, weekday: Int) -> some View {
        let selected = viewModel.workDays.contains(weekday)
        return Button {
            if selected {
                viewModel.workDays.removeAll { $0 == weekday }
            } else {
                viewModel.workDays.append(weekday)
            }
        } label: {
            Text(label)
                .font(Theme.body(13, weight: selected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(selected ? Theme.primary : Theme.background)
                .foregroundStyle(selected ? Color.white : Theme.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Color.clear : Theme.border, lineWidth: 1)
                )
        }
    }
}

@Observable
final class SetAgendaViewModel {
    var workDays: [Int] = SetAgendaPrefs.padrao.workDays
    var start = SetAgendaViewModel.date(from: "08:00")
    var end = SetAgendaViewModel.date(from: "18:00")
    var isLoading = true
    var isSaving = false
    var errorMessage: String?
    var showError = false

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter
    }()

    static func date(from time: String) -> Date {
        formatter.date(from: time) ?? Date()
    }

    @MainActor
    func load() async {
        defer { isLoading = false }
        do {
            let office: SetOffice = try await APIClient.shared.get("settings/office")
            let prefs = office.agenda ?? .padrao
            workDays = prefs.workDays
            start = Self.date(from: prefs.startTime)
            end = Self.date(from: prefs.endTime)
        } catch {
            present(error)
        }
    }

    @MainActor
    func save() async -> Bool {
        struct Body: Encodable { let agenda: SetAgendaPrefs }
        guard !workDays.isEmpty else {
            errorMessage = "Selecione pelo menos um dia de atendimento."
            showError = true
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let prefs = SetAgendaPrefs(
                workDays: workDays.sorted(),
                startTime: Self.formatter.string(from: start),
                endTime: Self.formatter.string(from: end)
            )
            let _: SetOffice = try await APIClient.shared.put("settings/office", body: Body(agenda: prefs))
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
