import SwiftUI
import UIKit

/// Logo do banco da conta para saque (2026-10-06, igual ao web). As logos
/// ficam em Resources/Bancos.xcassets como `banco-<ispb>` — marcas das
/// instituições, usadas só para identificar o banco (ver
/// AcolherCRM/assets-bancos/README.md). Banco sem logo: a inicial do nome;
/// sem banco descoberto: o ícone de chave de antes.
struct BancoLogo: View {
    let ispb: String?
    let nome: String?
    var tamanho: CGFloat = 36
    /// Conta padrão / selecionada: anel na cor primária.
    var destacado = false

    init(ispb: String?, nome: String?, tamanho: CGFloat = 36, destacado: Bool = false) {
        self.ispb = ispb
        self.nome = nome
        self.tamanho = tamanho
        self.destacado = destacado
    }

    init(banco: GwBank?, tamanho: CGFloat = 36, destacado: Bool = false) {
        self.init(
            ispb: banco?.logo == nil ? nil : banco?.ispb,
            nome: banco?.short,
            tamanho: tamanho,
            destacado: destacado
        )
    }

    private var imagem: UIImage? {
        guard let ispb, !ispb.isEmpty else { return nil }
        return UIImage(named: "banco-\(ispb)")
    }

    var body: some View {
        Group {
            if let imagem {
                Image(uiImage: imagem)
                    .resizable()
                    .scaledToFit()
                    .padding(tamanho * 0.06)
                    .frame(width: tamanho, height: tamanho)
                    .background(Color.white, in: Circle())
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                    .accessibilityLabel(Text(nome ?? "Banco"))
            } else if let inicial = nome?.trimmingCharacters(in: .whitespaces).first {
                Text(String(inicial).uppercased())
                    .font(.system(size: tamanho * 0.42, weight: .semibold))
                    .foregroundStyle(destacado ? Color.white : Theme.primary)
                    .frame(width: tamanho, height: tamanho)
                    .background(destacado ? Theme.primary : Theme.primarySoft, in: Circle())
                    .accessibilityLabel(Text(nome ?? "Banco"))
            } else {
                Image(systemName: "key")
                    .font(.system(size: tamanho * 0.38, weight: .semibold))
                    .foregroundStyle(destacado ? Color.white : Theme.primary)
                    .frame(width: tamanho, height: tamanho)
                    .background(destacado ? Theme.primary : Theme.primarySoft, in: Circle())
                    .accessibilityHidden(true)
            }
        }
        .padding(destacado ? 2 : 0)
        .overlay {
            if destacado, imagem != nil {
                Circle().stroke(Theme.primary, lineWidth: 2)
            }
        }
    }
}
