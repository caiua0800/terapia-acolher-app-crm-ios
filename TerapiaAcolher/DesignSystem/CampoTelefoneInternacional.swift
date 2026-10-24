import SwiftUI

// MARK: - Telefone com país

/// Número de WhatsApp com o país ao lado (2026-10-23). Só o miolo — botão do
/// país, divisória e campo —: a moldura (caixa, linha de formulário, cartão)
/// fica com cada tela, que já tinha a sua. As regras (máscara, detecção pelo
/// DDI, o que vai para a API) estão em `TelefoneInternacional`.
struct CampoTelefoneInternacional: View {
    /// ISO do país ("BR", "PT"…).
    @Binding var pais: String
    /// Número mascarado, sem o DDI.
    @Binding var numero: String
    var fonte: Font = Theme.body(16)
    var alinhamento: TextAlignment = .leading

    @State private var escolhendoPais = false

    private var atual: TelefoneInternacional.Pais { TelefoneInternacional.pais(pais) }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                escolhendoPais = true
            } label: {
                HStack(spacing: 5) {
                    Text(atual.bandeira).font(.system(size: 19))
                    Text("+\(atual.ddi)")
                        .font(fonte)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("País: \(atual.nome), +\(atual.ddi). Trocar país")

            Rectangle()
                .fill(Theme.border)
                .frame(width: 1, height: 22)

            TextField(pais == TelefoneInternacional.brasil ? "(11) 91234-5678" : "Número", text: $numero)
                .font(fonte)
                .foregroundStyle(Theme.textPrimary)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .multilineTextAlignment(alinhamento)
                .monospacedDigit()
                .onChange(of: numero) { _, novo in digitar(novo) }
        }
        .sheet(isPresented: $escolhendoPais) {
            ListaDePaises(atual: pais) { iso in
                pais = iso
                numero = TelefoneInternacional.mascara(iso, numero)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func digitar(_ valor: String) {
        // Colou "+1 415…" ou "+351…" (ou o autopreenchimento trouxe com DDI):
        // o país vem junto e o seletor troca sozinho.
        if valor.trimmingCharacters(in: .whitespaces).hasPrefix("+") {
            let digitos = valor.filter { $0.isASCII && $0.isNumber }
            if let achado = TelefoneInternacional.detectar(digitos) {
                pais = achado.iso
                let m = TelefoneInternacional.mascara(achado.iso, String(digitos.dropFirst(achado.ddi.count)))
                if m != numero { numero = m }
                return
            }
        }
        let m = TelefoneInternacional.mascara(pais, valor)
        if m != valor { numero = m }
    }
}

// MARK: - Lista de países (sheet com busca)

private struct ListaDePaises: View {
    let atual: String
    let aoEscolher: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var busca = ""

    /// Nome em PT-BR sem acento, DDI ("+44" ou "351") ou sigla ISO.
    private var filtrados: [TelefoneInternacional.Pais] {
        var termo = busca.trimmingCharacters(in: .whitespaces)
        if termo.hasPrefix("+") { termo.removeFirst() }
        termo = TelefoneInternacional.semAcento(termo)
        guard !termo.isEmpty else { return TelefoneInternacional.paises }
        return TelefoneInternacional.paises.filter {
            TelefoneInternacional.semAcento($0.nome).contains(termo)
                || $0.ddi.hasPrefix(termo)
                || $0.iso.lowercased() == termo
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filtrados.isEmpty {
                    Text("Nenhum país encontrado.")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filtrados) { p in
                        Button {
                            Haptics.tap()
                            aoEscolher(p.iso)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Text(p.bandeira).font(.system(size: 22))
                                Text(p.nome)
                                    .font(Theme.body(15, weight: p.iso == atual ? .semibold : .regular))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text("+\(p.ddi)")
                                    .font(Theme.body(15))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textSecondary)
                                if p.iso == atual {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.primary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .listRowBackground(Theme.surface)
                        .accessibilityAddTraits(p.iso == atual ? .isSelected : [])
                    }
                    .listStyle(.plain)
                }
            }
            .background(Theme.surface)
            .navigationTitle("País")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $busca,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Buscar país ou código…"
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}
