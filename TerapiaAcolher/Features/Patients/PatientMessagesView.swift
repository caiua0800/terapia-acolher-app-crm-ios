import SwiftUI

// MARK: - Mensagens enviadas ao paciente

/// Uma mensagem ao paciente (WhatsApp ou e-mail) com os recibos de entrega.
struct PatientMessage: Decodable, Identifiable, Equatable {
    let id: String
    let canal: String
    let tipo: String
    let destino: String
    let estado: String
    let criadaEm: Date
    let enviadaEm: Date?
    let entregueEm: Date?
    let lidaEm: Date?
    let erro: String?

    var isWhatsapp: Bool { canal == "WHATSAPP" }
}

struct PatientMessagesPage: Decodable {
    let itens: [PatientMessage]
    let total: Int
    let pagina: Int
    let porPagina: Int
}

@MainActor
@Observable
final class PatientMessagesViewModel {
    let patientId: String
    var itens: [PatientMessage] = []
    var total = 0
    var pagina = 0
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?

    init(patientId: String) { self.patientId = patientId }

    var temMais: Bool { itens.count < total }

    func load() async {
        isLoading = itens.isEmpty
        errorMessage = nil
        defer { isLoading = false }
        do {
            let p: PatientMessagesPage = try await APIClient.shared.get(
                "patients/\(patientId)/messages",
                query: ["pagina": "1"]
            )
            itens = p.itens
            total = p.total
            pagina = 1
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Não foi possível carregar as mensagens."
        }
    }

    func loadMore() async {
        guard temMais, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let p: PatientMessagesPage = try await APIClient.shared.get(
                "patients/\(patientId)/messages",
                query: ["pagina": String(pagina + 1)]
            )
            let novos = p.itens.filter { n in !itens.contains { $0.id == n.id } }
            itens.append(contentsOf: novos)
            total = p.total
            pagina = p.pagina
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Não foi possível carregar mais."
        }
    }
}

struct PatientMessagesView: View {
    let patientName: String
    @State private var model: PatientMessagesViewModel

    init(patientId: String, patientName: String) {
        self.patientName = patientName
        _model = State(initialValue: PatientMessagesViewModel(patientId: patientId))
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content
        }
        .navigationTitle("Mensagens")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView().tint(Theme.primary)
        } else if let erro = model.errorMessage, model.itens.isEmpty {
            VStack(spacing: 14) {
                Text(erro)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                RetryButton { Task { await model.load() } }
            }
            .padding(.horizontal, 32)
        } else if model.itens.isEmpty {
            ScrollView {
                EmptyStateView(
                    icon: "bubble.left.and.text.bubble.right",
                    title: "Nenhuma mensagem ainda",
                    message: "Confirmações e lembretes de sessão e de cobrança enviados a este paciente aparecem aqui, com o que chegou e o que foi lido."
                )
            }
            .refreshable { await model.load() }
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    Text("\(model.total) \(model.total == 1 ? "mensagem enviada" : "mensagens enviadas") a \(patientName) por WhatsApp e e-mail")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(model.itens) { m in
                        MessageCard(m: m)
                    }
                    if model.temMais {
                        Button {
                            Haptics.tap()
                            Task { await model.loadMore() }
                        } label: {
                            HStack(spacing: 8) {
                                if model.isLoadingMore { ProgressView().controlSize(.small) }
                                Text("Ver mais")
                            }
                            .font(Theme.body(14, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().stroke(Theme.border))
                        }
                        .buttonStyle(.pressable)
                        .disabled(model.isLoadingMore)
                    }
                    Text("“Lida” só aparece quando o paciente deixa a confirmação de leitura ligada no WhatsApp. No e-mail, dá para saber se chegou, não se foi aberto.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .padding(Theme.screenPadding)
            }
            .refreshable { await model.load() }
            .accessibilityIdentifier("patientMessagesList")
        }
    }
}

private struct MessageCard: View {
    let m: PatientMessage

    private static let data: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "dd/MM/yy 'às' HH:mm"
        return f
    }()

    private func quando(_ d: Date?) -> String { d.map { Self.data.string(from: $0) } ?? "—" }

    private var selo: (String, Color, Color) {
        switch m.estado {
        case "NA_FILA": return ("Na fila", Theme.textSecondary, Theme.border)
        case "ENVIADA": return (m.isWhatsapp ? "Enviada" : "Enviado", Theme.textPrimary, Theme.border)
        case "ENTREGUE": return (m.isWhatsapp ? "Entregue" : "Chegou", Theme.success, Theme.successSoft)
        case "LIDA": return ("Lida", Color(hex: 0x2A6FB0), Color(hex: 0xDCEFFF))
        case "ATRASADA": return ("Atrasada", Theme.warning, Theme.warningSoft)
        case "DEVOLVIDA": return ("Não chegou", Theme.danger, Theme.dangerSoft)
        case "SPAM": return ("Marcada como spam", Theme.danger, Theme.dangerSoft)
        default: return ("Falhou", Theme.danger, Theme.dangerSoft)
        }
    }

    var body: some View {
        ThemeCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: m.isWhatsapp ? "message.fill" : "envelope.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(m.isWhatsapp ? Color(hex: 0x1F9E4F) : Theme.primary)
                    .frame(width: 38, height: 38)
                    .background(m.isWhatsapp ? Color(hex: 0xE3F5EA) : Theme.primarySoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(m.tipo)
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        StatusBadge(label: selo.0, color: selo.1, background: selo.2)
                    }
                    Text("\(m.isWhatsapp ? "WhatsApp" : "E-mail") · \(m.destino)")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(alignment: .top, spacing: 16) {
                        if m.isWhatsapp {
                            campo("Enviada", quando(m.enviadaEm), m.enviadaEm != nil)
                            campo("Entregue", quando(m.entregueEm), m.entregueEm != nil)
                            campo("Lida", quando(m.lidaEm), m.lidaEm != nil)
                        } else {
                            campo("Enviado", quando(m.enviadaEm), m.enviadaEm != nil)
                            campo("Chegou", quando(m.entregueEm), m.entregueEm != nil)
                        }
                    }
                    .padding(.top, 2)
                    if let erro = m.erro {
                        Text(erro)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.danger)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func campo(_ rotulo: String, _ valor: String, _ tem: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(rotulo.uppercased())
                .font(Theme.body(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
            Text(valor)
                .font(Theme.body(12))
                .foregroundStyle(tem ? Theme.textPrimary : Theme.textSecondary)
        }
    }
}
