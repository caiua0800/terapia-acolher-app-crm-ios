import Foundation

/// Tudo que guarda dado do terapeuta logado entre uma tela e outra.
///
/// As listas principais vivem em instâncias únicas (`shared`) para a tela
/// voltar já pintada, sem spinner. O preço: sem este reset, o próximo
/// terapeuta a entrar no mesmo aparelho abria Início, Agenda, Pacientes e
/// Financeiro com os dados do anterior até cada tela recarregar — e, sem
/// rede, ficava com eles. Dado de saúde na conta errada.
///
/// Trocar a instância (e não limpar campo a campo) garante que nada fique
/// para trás quando uma tela ganhar estado novo. As views pegam a instância
/// nova sozinhas: o `MainShellView` sai da tela no logout e, no próximo login,
/// cada `@State ... = X.shared` é avaliado de novo.
///
/// Tela nova com `static var shared` de dado do usuário: acrescentar aqui.
@MainActor
enum SessionScope {
    static func reset() {
        DashboardViewModel.shared = DashboardViewModel()
        AgendaViewModel.shared = AgendaViewModel()
        PatientsListViewModel.shared = PatientsListViewModel()
        RecordsHomeViewModel.shared = RecordsHomeViewModel()
        TranscriptsPatientsViewModel.shared = TranscriptsPatientsViewModel()
        FinHomeViewModel.shared = FinHomeViewModel()
        FinGatewayStore.shared = FinGatewayStore()
        NotificationsViewModel.shared = NotificationsViewModel()
        VitrineViewModel.shared = VitrineViewModel()
        LeadsStore.shared = LeadsStore()
        SubscriptionViewModel.shared = SubscriptionViewModel()
        SettingsHomeViewModel.shared = SettingsHomeViewModel()
        SetGroupsViewModel.shared = SetGroupsViewModel()
        SetTemplatesViewModel.shared = SetTemplatesViewModel()
        UsageViewModel.shared = UsageViewModel()

        // Fotos de paciente e do suporte: só memória, mas do usuário que saiu.
        RemoteImageCache.shared.limparTudo()
        SupImageCache.shared.limparTudo()
    }
}
