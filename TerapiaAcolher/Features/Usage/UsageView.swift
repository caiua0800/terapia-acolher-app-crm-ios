import Observation
import SwiftUI

// MARK: - Payload do GET /usage (espelho do UsageService)

struct UsageMonth: Decodable, Identifiable, Hashable {
    /// "AAAA-MM"
    let mes: String
    /// Mensagens de WhatsApp entregues a pacientes (sem o código de verificação).
    let whatsapp: Int
    /// Resumos de transcrição gerados pela IA.
    let resumos: Int
    /// IA no prontuário e na anamnese (um recurso só).
    let iaRegistros: Int

    var id: String { mes }
}

struct UsagePayload: Decodable {
    struct PorTipo: Decodable, Identifiable {
        let template: String
        let rotulo: String
        let total: Int
        var id: String { template }
    }

    let mesAtual: String
    let atual: UsageMonth
    let historico: [UsageMonth]
    let whatsappPorTipo: [PorTipo]
}

// MARK: - ViewModel

@Observable
final class UsageViewModel {
    /// Instância única: volta pintada. `var`: o logout troca (ver SessionScope).
    static var shared = UsageViewModel()

    var payload: UsagePayload?
    var isLoading = false
    var errorMessage: String?
    var isRetrying = false

    @MainActor
    func load() async {
        if payload == nil { isLoading = true }
        if errorMessage != nil { isRetrying = true }
        errorMessage = nil
        defer { isLoading = false; isRetrying = false }
        do {
            payload = try await APIClient.shared.get("usage", query: ["meses": "12"])
        } catch is CancellationError {
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar o uso da conta."
        }
    }
}

// MARK: - Recursos contados

enum UsageResource: CaseIterable, Identifiable {
    case whatsapp, resumos, iaRegistros

    var id: Self { self }

    var titulo: String {
        switch self {
        case .whatsapp: "Mensagens de WhatsApp"
        case .resumos: "Resumos de transcrição"
        case .iaRegistros: "IA no prontuário e anamnese"
        }
    }

    var unidade: (String, String) {
        switch self {
        case .whatsapp: ("mensagem", "mensagens")
        case .resumos: ("resumo", "resumos")
        case .iaRegistros: ("uso", "usos")
        }
    }

    var explica: String {
        switch self {
        case .whatsapp: "Lembretes, confirmações e cobranças entregues aos seus pacientes."
        case .resumos: "Resumos das sessões online feitos pela IA."
        case .iaRegistros: "Vezes em que a IA organizou seu rascunho nos campos do modelo."
        }
    }

    var icon: String {
        switch self {
        case .whatsapp: "message.fill"
        case .resumos: "waveform"
        case .iaRegistros: "sparkles"
        }
    }

    var cor: Color {
        switch self {
        case .whatsapp: Color(hex: 0x1F9E4F)
        case .resumos: Color(hex: 0x7E5FC0)
        case .iaRegistros: Theme.primary
        }
    }

    var fundo: Color {
        switch self {
        case .whatsapp: Color(hex: 0xE3F5EA)
        case .resumos: Color(hex: 0xEFE9F8)
        case .iaRegistros: Theme.primarySoft
        }
    }

    func valor(_ mes: UsageMonth) -> Int {
        switch self {
        case .whatsapp: mes.whatsapp
        case .resumos: mes.resumos
        case .iaRegistros: mes.iaRegistros
        }
    }
}

enum UsageFormat {
    private static let longo: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "LLLL 'de' yyyy"
        return f
    }()

    private static let curto: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "LLL"
        return f
    }()

    private static func data(_ mes: String) -> Date? {
        let partes = mes.split(separator: "-").compactMap { Int($0) }
        guard partes.count == 2 else { return nil }
        var c = DateComponents()
        c.year = partes[0]; c.month = partes[1]; c.day = 1
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)
    }

    /// "Setembro de 2026" (ou "Set" no curto).
    static func nome(_ mes: String, curto: Bool = false) -> String {
        guard let d = data(mes) else { return mes }
        let texto = (curto ? self.curto : longo).string(from: d).replacingOccurrences(of: ".", with: "")
        return texto.prefix(1).uppercased() + texto.dropFirst()
    }
}

// MARK: - Tela

/// Uso da conta, mês a mês. Os números vêm do registro de cada envio e de cada
/// chamada à IA — o mês passado nunca muda depois de fechado.
struct UsageView: View {
    @State private var model = UsageViewModel.shared

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if let payload = model.payload {
                content(payload)
            } else if model.isLoading {
                ProgressView().tint(Theme.primary)
            } else if let error = model.errorMessage {
                VStack(spacing: 14) {
                    EmptyStateView(icon: "wifi.exclamationmark", title: "Ops, não carregou", message: error)
                    RetryButton(isLoading: model.isRetrying) {
                        Task { await model.load() }
                    }
                }
            }
        }
        .setToolbarTitle("Uso da conta")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await model.load() } }
    }

    private func content(_ p: UsagePayload) -> some View {
        let anterior = p.historico.count > 1 ? p.historico[p.historico.count - 2] : nil
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(UsageFormat.nome(p.mesAtual)) até agora")
                        .font(Theme.serifTitle(22))
                        .foregroundStyle(Theme.textPrimary)
                    Text("O mês fecha no último dia, no horário de Brasília.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                }

                ForEach(UsageResource.allCases) { recurso in
                    resourceCard(recurso, atual: p.atual, anterior: anterior)
                }

                whatsappByType(p.whatsappPorTipo)
                history(p.historico)

                Text("Contamos só o que foi entregue: mensagem que falhou no envio ou chamada à IA que deu erro não entram. Cada mês fica guardado — dá para comparar quando quiser.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .refreshable { await model.load() }
    }

    private func resourceCard(_ r: UsageResource, atual: UsageMonth, anterior: UsageMonth?) -> some View {
        let valor = r.valor(atual)
        let antes = anterior.map(r.valor) ?? 0
        let diff = valor - antes
        let comparacao: String = {
            guard anterior != nil else { return r.explica }
            if diff == 0 { return "Igual ao mês passado (\(antes))." }
            return "\(diff > 0 ? "+" : "−")\(abs(diff)) em relação ao mês passado (\(antes))."
        }()
        return ThemeCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: r.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(r.cor)
                        .frame(width: 40, height: 40)
                        .background(r.fundo, in: RoundedRectangle(cornerRadius: 12))
                    Text(r.titulo)
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(valor)")
                        .font(Theme.moneyDisplay(32))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(valor == 1 ? r.unidade.0 : r.unidade.1) neste mês")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(comparacao)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                if anterior != nil {
                    Divider()
                    Text(r.explica)
                        .font(Theme.body(11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func whatsappByType(_ tipos: [UsagePayload.PorTipo]) -> some View {
        let total = max(tipos.reduce(0) { $0 + $1.total }, 1)
        return ThemeCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("WhatsApp neste mês, por tipo")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("O código que confirma o seu número no CRM não entra na conta.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if tipos.isEmpty {
                    Text("Nenhuma mensagem enviada a pacientes neste mês.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                } else {
                    ForEach(tipos) { t in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(t.rotulo)
                                    .font(Theme.body(13.5))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text("\(t.total)")
                                    .font(Theme.money(14, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.border.opacity(0.6))
                                    Capsule()
                                        .fill(Color(hex: 0x25D366))
                                        .frame(width: geo.size.width * CGFloat(t.total) / CGFloat(total))
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func history(_ meses: [UsageMonth]) -> some View {
        let maior = max(meses.flatMap { [$0.whatsapp, $0.resumos, $0.iaRegistros] }.max() ?? 1, 1)
        let totais = (
            meses.reduce(0) { $0 + $1.whatsapp },
            meses.reduce(0) { $0 + $1.resumos },
            meses.reduce(0) { $0 + $1.iaRegistros }
        )
        return ThemeCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Últimos 12 meses")
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(meses) { m in
                        VStack(spacing: 5) {
                            HStack(alignment: .bottom, spacing: 1.5) {
                                ForEach(UsageResource.allCases) { r in
                                    let v = r.valor(m)
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(r == .whatsapp ? Color(hex: 0x25D366) : r.cor)
                                        .frame(height: v == 0 ? 0 : max(3, 100 * CGFloat(v) / CGFloat(maior)))
                                }
                            }
                            .frame(height: 100, alignment: .bottom)
                            Text(UsageFormat.nome(m.mes, curto: true))
                                .font(Theme.body(9))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(UsageResource.allCases) { r in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(r == .whatsapp ? Color(hex: 0x25D366) : r.cor)
                                .frame(width: 7, height: 7)
                            Text(r.titulo)
                                .font(Theme.body(11.5))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }

                VStack(spacing: 0) {
                    tableRow("Mês", "WhatsApp", "Resumos", "IA", header: true)
                    ForEach(Array(meses.reversed().enumerated()), id: \.element.id) { i, m in
                        Divider()
                        tableRow(
                            UsageFormat.nome(m.mes) + (i == 0 ? " (atual)" : ""),
                            "\(m.whatsapp)", "\(m.resumos)", "\(m.iaRegistros)",
                            bold: i == 0
                        )
                    }
                    Divider()
                    tableRow("Total em 12 meses", "\(totais.0)", "\(totais.1)", "\(totais.2)", bold: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tableRow(
        _ a: String, _ b: String, _ c: String, _ d: String,
        header: Bool = false, bold: Bool = false
    ) -> some View {
        let fonte = header
            ? Theme.body(10.5, weight: .semibold)
            : Theme.body(12.5, weight: bold ? .semibold : .regular)
        let cor = header ? Theme.textSecondary : Theme.textPrimary
        return HStack(spacing: 8) {
            Text(header ? a.uppercased() : a)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(header ? b.uppercased() : b).frame(width: 64, alignment: .trailing)
            Text(header ? c.uppercased() : c).frame(width: 60, alignment: .trailing)
            Text(header ? d.uppercased() : d).frame(width: 36, alignment: .trailing)
        }
        .font(fonte)
        .monospacedDigit()
        .foregroundStyle(cor)
        .padding(.vertical, 8)
    }
}
