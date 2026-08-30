import Observation
import SwiftUI

@Observable
final class VitrineProfileViewModel {
    var perfil: VitrineProfile?
    var options: VitrineOptions?

    var name = ""
    var bio = ""
    var city = ""
    var state = ""
    var whatsapp = ""
    var priceText = ""
    var specialties: Set<String> = []
    var approaches: Set<String> = []
    var targetAudience: Set<String> = []
    var shifts: Set<String> = []
    var modalities: Set<String> = []

    var isLoading = true
    var isSaving = false
    var errorMessage: String?
    var alerta: String?
    var showAlerta = false
    var salvou = false

    /// Limite da bio na Vitrine. Deixar o terapeuta escrever 3.000 caracteres
    /// e só descobrir no "salvar" é o pior momento pra avisar.
    static let bioMax = 1000

    @MainActor
    func load() async {
        isLoading = perfil == nil
        errorMessage = nil
        do {
            async let p = VitrineAPI.profile()
            async let o = VitrineAPI.options()
            let (perfil, options) = try await (p, o)
            self.perfil = perfil
            self.options = options
            preencher(perfil)
        } catch is CancellationError {
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar seu perfil da Vitrine."
        }
        isLoading = false
    }

    private func preencher(_ p: VitrineProfile) {
        name = p.name ?? ""
        bio = p.bio ?? ""
        city = p.city ?? ""
        state = p.state ?? ""
        whatsapp = p.whatsapp ?? ""
        priceText = p.consultationPrice.map { String(format: "%.2f", $0).replacingOccurrences(of: ".", with: ",") } ?? ""
        specialties = Set(p.specialties ?? [])
        approaches = Set(p.approaches ?? [])
        targetAudience = Set(p.targetAudience ?? [])
        shifts = Set(p.shifts ?? [])
        modalities = Set(p.modalities ?? [])
    }

    var price: Double? {
        let limpo = priceText
            .replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return limpo.isEmpty ? nil : Double(limpo)
    }

    @MainActor
    func save() async -> Bool {
        if !priceText.isEmpty && price == nil {
            present("Valor da consulta inválido.")
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            // Só o que o formulário mostra. Mandar o objeto inteiro faria o app
            // sobrescrever, com dado velho, campos que ele nem exibe.
            try await VitrineAPI.save(
                VitrineProfilePatch(
                    name: name.trimmingCharacters(in: .whitespaces),
                    bio: bio,
                    state: state.isEmpty ? nil : state,
                    city: city.isEmpty ? nil : city,
                    whatsapp: whatsapp.isEmpty ? nil : whatsapp,
                    modalities: Array(modalities),
                    specialties: Array(specialties),
                    targetAudience: Array(targetAudience),
                    shifts: Array(shifts),
                    approaches: Array(approaches),
                    languages: nil,
                    consultationPrice: price
                )
            )
            Haptics.success()
            salvou = true
            return true
        } catch let error as APIError {
            // A validação de verdade é a da Vitrine — ela é dona do dado.
            // Mostramos a mensagem dela, não uma genérica nossa.
            present(error.message)
        } catch {
            present("Não foi possível salvar. Verifique sua conexão.")
        }
        return false
    }

    @MainActor
    private func present(_ mensagem: String) {
        alerta = mensagem
        showAlerta = true
    }
}

/// Edição do perfil da Vitrine. A Vitrine continua DONA do dado: aqui não há
/// cópia local, o formulário carrega dela e salva nela. Sem cópia não existe
/// sincronização, e sem sincronização não existe conflito.
struct VitrineProfileView: View {
    @State private var model = VitrineProfileViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content
        }
        .setToolbarTitle("Meu perfil na Vitrine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    Task { if await model.save() { dismiss() } }
                } label: {
                    if model.isSaving {
                        ProgressView().controlSize(.small).tint(Theme.primary)
                    } else {
                        Text("Salvar").font(Theme.body(16, weight: .semibold))
                    }
                }
                .disabled(model.isSaving || model.isLoading)
            }
        }
        .task { await model.load() }
        .alert("Ops", isPresented: $model.showAlerta) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alerta ?? "Algo deu errado.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView().tint(Theme.primary)
        } else if let erro = model.errorMessage {
            ErrorRetryView(message: erro) { Task { await model.load() } }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    dadosCard
                    bioCard
                    multiCard("ESPECIALIDADES", opcoes: model.options?.specialties, selecao: $model.specialties)
                    multiCard("ABORDAGENS", opcoes: model.options?.approaches, selecao: $model.approaches)
                    multiCard("ATENDE", opcoes: model.options?.targetAudience, selecao: $model.targetAudience)
                    multiCard("TURNOS", opcoes: model.options?.shifts, selecao: $model.shifts)
                    multiCard("MODALIDADE", opcoes: model.options?.modalities, selecao: $model.modalities)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
    }

    private var dadosCard: some View {
        ThemeCard(padding: 0) {
            VStack(spacing: 0) {
                campo("Nome", texto: $model.name)
                Divider().overlay(Theme.border)
                campo("Cidade", texto: $model.city)
                Divider().overlay(Theme.border)
                campo("UF", texto: $model.state, maiusculo: true)
                Divider().overlay(Theme.border)
                campo("WhatsApp", texto: $model.whatsapp, teclado: .phonePad)
                Divider().overlay(Theme.border)
                campo("Valor da consulta", texto: $model.priceText, teclado: .decimalPad)
            }
        }
    }

    private func campo(
        _ rotulo: String,
        texto: Binding<String>,
        teclado: UIKeyboardType = .default,
        maiusculo: Bool = false
    ) -> some View {
        HStack {
            Text(rotulo)
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 12)
            TextField("", text: texto)
                .font(Theme.body(15))
                .keyboardType(teclado)
                .autocorrectionDisabled()
                .textInputAutocapitalization(maiusculo ? .characters : .sentences)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private var bioCard: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SOBRE VOCÊ")
                        .font(Theme.body(10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(model.bio.count)/\(VitrineProfileViewModel.bioMax)")
                        .font(Theme.body(11))
                        .foregroundStyle(
                            model.bio.count > VitrineProfileViewModel.bioMax
                                ? Theme.danger : Theme.textSecondary
                        )
                }

                TextEditor(text: $model.bio)
                    .font(Theme.body(15))
                    .frame(minHeight: 130)
                    .scrollContentBackground(.hidden)

                if model.bio.isEmpty {
                    // O aviso vale mais que o campo: perfil sem bio é o que
                    // mais custa clique, e é onde o app justifica existir.
                    Text("Perfis com uma apresentação recebem bem mais contatos.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.warning)
                }
            }
        }
    }

    private func multiCard(
        _ titulo: String,
        opcoes: [String]?,
        selecao: Binding<Set<String>>
    ) -> some View {
        // As listas vêm da Vitrine. NUNCA redeclarar aqui — foi assim que a
        // opção "Outra" sumiu do cadastro no sistema antigo deles.
        ThemeCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(titulo)
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)

                if let opcoes, !opcoes.isEmpty {
                    FlowChips(opcoes: opcoes, selecao: selecao)
                } else {
                    Text("Não foi possível carregar as opções.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

/// Chips que quebram linha sozinhos.
struct FlowChips: View {
    let opcoes: [String]
    @Binding var selecao: Set<String>

    var body: some View {
        FlexibleStack(opcoes, spacing: 8) { opcao in
            let ativo = selecao.contains(opcao)
            Button {
                Haptics.tap()
                if ativo { selecao.remove(opcao) } else { selecao.insert(opcao) }
            } label: {
                Text(opcao)
                    .font(Theme.body(13, weight: ativo ? .semibold : .regular))
                    .foregroundStyle(ativo ? Theme.primary : Theme.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(ativo ? Theme.primarySoft : Theme.background, in: Capsule())
                    .overlay(
                        Capsule().stroke(ativo ? Theme.primary : Theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.pressable)
        }
    }
}

/// Layout que empilha em linhas conforme a largura disponível.
struct FlexibleStack<Item: Hashable, Conteudo: View>: View {
    let itens: [Item]
    let spacing: CGFloat
    let conteudo: (Item) -> Conteudo

    init(_ itens: [Item], spacing: CGFloat = 8, @ViewBuilder conteudo: @escaping (Item) -> Conteudo) {
        self.itens = itens
        self.spacing = spacing
        self.conteudo = conteudo
    }

    var body: some View {
        FlowLayout(spacing: spacing) {
            ForEach(itens, id: \.self) { conteudo($0) }
        }
    }
}

/// `Layout` nativo: mede cada chip e quebra a linha quando não cabe.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largura = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, alturaLinha: CGFloat = 0
        for sub in subviews {
            let t = sub.sizeThatFits(.unspecified)
            if x + t.width > largura, x > 0 {
                x = 0
                y += alturaLinha + spacing
                alturaLinha = 0
            }
            x += t.width + spacing
            alturaLinha = max(alturaLinha, t.height)
        }
        return CGSize(width: largura, height: y + alturaLinha)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, alturaLinha: CGFloat = 0
        for sub in subviews {
            let t = sub.sizeThatFits(.unspecified)
            if x + t.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += alturaLinha + spacing
                alturaLinha = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + spacing
            alturaLinha = max(alturaLinha, t.height)
        }
    }
}
