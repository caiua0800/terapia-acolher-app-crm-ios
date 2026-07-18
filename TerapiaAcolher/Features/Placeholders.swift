import SwiftUI

// ⚠️ ARQUIVO TEMPORÁRIO DE INTEGRAÇÃO.
// Cada view abaixo é um slot do shell. Os agentes de feature criam a
// implementação real com O MESMO NOME em Features/<Área>/ e REMOVEM
// a placeholder correspondente daqui. No fim, este arquivo some.

enum RecordsKind { case record, anamnesis }

struct DashboardView: View {
    var body: some View { FeaturePlaceholder(title: "Início") }
}

struct AgendaView: View {
    var body: some View { FeaturePlaceholder(title: "Agenda") }
}

struct PatientsListView: View {
    var body: some View { FeaturePlaceholder(title: "Pacientes") }
}

struct RecordsHomeView: View {
    let kind: RecordsKind
    var body: some View { FeaturePlaceholder(title: kind == .record ? "Prontuários" : "Anamneses") }
}

struct FinanceHomeView: View {
    var body: some View { FeaturePlaceholder(title: "Financeiro") }
}

struct DocumentsHomeView: View {
    var body: some View { FeaturePlaceholder(title: "Documentos") }
}

struct FilesHomeView: View {
    var body: some View { FeaturePlaceholder(title: "Arquivos") }
}

struct SettingsHomeView: View {
    var body: some View { FeaturePlaceholder(title: "Configurações") }
}

struct NotificationsView: View {
    var body: some View { FeaturePlaceholder(title: "Notificações") }
}

struct LoginFlowView: View {
    var body: some View { FeaturePlaceholder(title: "Login") }
}

struct FeaturePlaceholder: View {
    let title: String

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: "hammer")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.primary.opacity(0.5))
                Text(title)
                    .font(Theme.serifTitle(22))
                Text("Em construção")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
