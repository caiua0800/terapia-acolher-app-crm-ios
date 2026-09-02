import Observation
import PhotosUI
import SwiftUI

/// Config · Meu perfil — fiel ao MVP: avatar com botão de câmera,
/// DADOS PROFISSIONAIS, CONTATO e ASSINATURA EM DOCUMENTOS + Sair.
struct SetProfileView: View {
    @State private var viewModel = SetProfileViewModel()
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var signaturePickerItem: PhotosPickerItem?
    @State private var showSignatureCanvas = false
    @State private var showLogoutConfirm = false
    @State private var showVerifyPhone = false
    @State private var profileStatus = ProfileStatusStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    avatarHeader
                    pendencias
                    dadosProfissionais
                    contato
                    assinatura
                    sairButton
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 16)
            }
        }
        .setToolbarTitle("Meu perfil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.saveProfile() }
                } label: {
                    if viewModel.isSaving {
                        ProgressView().tint(Theme.primary)
                    } else {
                        Text("Salvar")
                            .font(Theme.body(16, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                    }
                }
                .disabled(viewModel.isSaving)
            }
        }
        .task {
            await viewModel.load()
            await profileStatus.refresh()
        }
        .sheet(isPresented: $showVerifyPhone) {
            SetVerifyPhoneView(numeroAtual: viewModel.whatsapp) {
                Task { await viewModel.load() }
            }
        }
        .onChange(of: avatarPickerItem) { _, item in
            guard let item else { return }
            Task {
                await viewModel.uploadImage(from: item, kind: .avatar)
                avatarPickerItem = nil
            }
        }
        .onChange(of: signaturePickerItem) { _, item in
            guard let item else { return }
            Task {
                await viewModel.uploadImage(from: item, kind: .signature)
                signaturePickerItem = nil
            }
        }
        .sheet(isPresented: $showSignatureCanvas) {
            SetSignatureCanvasView { pngData in
                Task { await viewModel.uploadSignaturePNG(pngData) }
            }
        }
        .alert("Ops", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Algo deu errado.")
        }
        .alert("Tudo certo", isPresented: $viewModel.showSaved) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.savedMessage)
        }
    }


    // MARK: - Pendências do perfil

    /// Repete no perfil o que o aviso do Início anuncia. É aqui que a pendência
    /// se resolve, então é aqui que ela precisa estar por escrito — o modal só
    /// avisa e traz para cá.
    @ViewBuilder
    private var pendencias: some View {
        if let status = profileStatus.status, status.temPendencia {
            VStack(spacing: 8) {
                SetSectionHeader(title: "Falta pouco")
                ThemeCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(status.pendenciasVisiveis.enumerated()), id: \.element.id) { indice, item in
                            if indice > 0 { Divider().padding(.leading, 52) }
                            pendenciaRow(item)
                        }
                    }
                }
            }
        }
    }

    private func pendenciaRow(_ item: ProfilePendency) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 15))
                .foregroundStyle(Theme.warning)
                .frame(width: 32, height: 32)
                .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(item.description)
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if item.code == "WHATSAPP_NAO_VERIFICADO" || item.code == "WHATSAPP_AUSENTE" {
                Button("Verificar") { showVerifyPhone = true }
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.primary)
            } else if item.code == "EMAIL_NAO_VERIFICADO" {
                Button(viewModel.isResendingEmail ? "Enviando…" : "Reenviar") {
                    Task { await viewModel.resendVerificationEmail() }
                }
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .disabled(viewModel.isResendingEmail)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// Selo embaixo do campo: o estado do número é a informação que explica
    /// por que os avisos chegam ou não.
    @ViewBuilder
    private var selosDoNumero: some View {
        if let status = profileStatus.status, status.whatsappEnabled {
            HStack(spacing: 8) {
                if status.phoneVerifiedAt != nil {
                    Label("Verificado", systemImage: "checkmark.seal.fill")
                        .font(Theme.body(12, weight: .semibold))
                        .foregroundStyle(Theme.success)
                } else {
                    Label("Não verificado", systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.body(12, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                    Button("Verificar agora") { showVerifyPhone = true }
                        .font(Theme.body(12, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                }
            }
        }
    }

    // MARK: - Avatar

    private var avatarHeader: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                RemoteAvatar(
                    url: viewModel.avatarURL,
                    name: viewModel.name.isEmpty ? "?" : viewModel.name,
                    size: 96
                )

                PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                    ZStack {
                        Circle()
                            .fill(Theme.primary)
                            .frame(width: 30, height: 30)
                        if viewModel.isUploadingAvatar {
                            ProgressView().tint(.white).scaleEffect(0.6)
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.white)
                        }
                    }
                    .overlay(Circle().stroke(Theme.background, lineWidth: 2.5))
                }
            }

            Text(viewModel.name.isEmpty ? "Seu nome" : viewModel.name)
                .font(Theme.serifTitle(22))
                .foregroundStyle(Theme.textPrimary)
            if !viewModel.specialty.isEmpty {
                Text(viewModel.specialty)
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(Theme.primary)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Seções

    private var dadosProfissionais: some View {
        VStack(spacing: 8) {
            SetSectionHeader(title: "Dados profissionais")
            ThemeCard(padding: 0) {
                VStack(spacing: 0) {
                    campoRow(icon: "person", color: Theme.primary, label: "Nome completo") {
                        TextField("Seu nome", text: $viewModel.name)
                    }
                    Divider().padding(.leading, 62)
                    campoRow(icon: "doc.text", color: Color(hex: 0x8FBCA6), label: "Especialidade") {
                        TextField("Ex.: Psicologia", text: $viewModel.specialty)
                    }
                    Divider().padding(.leading, 62)
                    campoRow(icon: "lanyardcard", color: Color(hex: 0xB9A6D9), label: "Registro profissional") {
                        TextField("Ex.: CRP 06/54321", text: $viewModel.registration)
                    }
                }
            }
        }
    }

    private var contato: some View {
        VStack(spacing: 8) {
            SetSectionHeader(title: "Contato")
            ThemeCard(padding: 0) {
                VStack(spacing: 0) {
                    campoRow(icon: "envelope", color: Color(hex: 0xB9A6D9), label: "E-mail") {
                        Text(viewModel.email)
                            .font(Theme.body(15))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider().padding(.leading, 62)
                    campoRow(icon: "phone", color: Theme.primary, label: "WhatsApp") {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("+55 (11) 91234-5678", text: $viewModel.whatsapp)
                                .keyboardType(.phonePad)
                                // Mesma máscara do cadastro de paciente: o número do
                                // terapeuta ia cru para o banco e era a última porta
                                // por onde entrava telefone sem DDI.
                                .onChange(of: viewModel.whatsapp) { _, novo in
                                    let m = PatientMask.whatsapp(novo)
                                    if m != novo { viewModel.whatsapp = m }
                                }
                            selosDoNumero
                        }
                    }
                }
            }
        }
    }

    private var assinatura: some View {
        VStack(spacing: 8) {
            SetSectionHeader(title: "Assinatura em documentos")
            ThemeCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("PRÉ-VISUALIZAÇÃO")
                        .font(Theme.body(11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .tracking(1)

                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.background)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [5]))
                            )
                        if viewModel.isUploadingSignature {
                            ProgressView().tint(Theme.primary)
                        } else if let url = viewModel.signatureURL {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFit().padding(10)
                                } else {
                                    ProgressView().tint(Theme.primary)
                                }
                            }
                        } else {
                            Text("Nenhuma assinatura cadastrada")
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(height: 110)

                    HStack(spacing: 10) {
                        Button {
                            showSignatureCanvas = true
                        } label: {
                            Label("Desenhar", systemImage: "signature")
                                .font(Theme.body(14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Theme.primary)
                                .clipShape(Capsule())
                        }
                        PhotosPicker(selection: $signaturePickerItem, matching: .images) {
                            Label("Enviar foto", systemImage: "photo")
                                .font(Theme.body(14, weight: .semibold))
                                .foregroundStyle(Theme.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Theme.primarySoft)
                                .clipShape(Capsule())
                        }
                    }

                    Text("A assinatura aparece nos PDFs gerados em Documentos (recibos, atestados, contratos).")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var sairButton: some View {
        Button {
            showLogoutConfirm = true
        } label: {
            Label("Sair da conta", systemImage: "rectangle.portrait.and.arrow.right")
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.dangerSoft)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .confirmationDialog(
            "Sair da conta?",
            isPresented: $showLogoutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sair", role: .destructive) {
                Task { await SessionStore.shared.logout() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Você vai precisar entrar de novo com e-mail e senha.")
        }
        .padding(.top, 4)
    }

    private func campoRow(
        icon: String,
        color: Color,
        label: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(label.uppercased())
                    .font(Theme.body(10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .tracking(0.7)
                content()
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(.horizontal, Theme.cardPadding)
        .padding(.vertical, 11)
    }
}

// MARK: - ViewModel

@Observable
final class SetProfileViewModel {
    enum ImageKind { case avatar, signature }

    var name = ""
    var specialty = ""
    var registration = ""
    var whatsapp = ""
    var email = ""
    var avatarURL: URL?
    var signatureURL: URL?
    var isSaving = false
    var isUploadingAvatar = false
    var isUploadingSignature = false
    var errorMessage: String?
    var showError = false
    var showSaved = false
    var isResendingEmail = false
    /// O mesmo alerta serve a salvar o perfil e a reenviar o e-mail; sem isto
    /// o reenvio anunciava "perfil atualizado", que não foi o que aconteceu.
    var savedMessage = "Perfil atualizado com sucesso."

    /// Reenvia o link de confirmação de e-mail para quem ainda não confirmou.
    @MainActor
    func resendVerificationEmail() async {
        struct Body: Encodable { let email: String }
        isResendingEmail = true
        defer { isResendingEmail = false }
        let _: MessageResponse? = try? await APIClient.shared.post(
            "auth/resend-verification",
            body: Body(email: email)
        )
        savedMessage = "Enviamos um novo link de confirmação para \(email)."
        showSaved = true
    }

    @MainActor
    func load() async {
        if let user = SessionStore.shared.user {
            name = user.name
            specialty = user.specialty ?? ""
            registration = user.professionalRegistration ?? ""
            // O banco guarda "5517992562727"; a tela mostra formatado.
            whatsapp = PatientMask.whatsapp(user.whatsapp ?? "")
            email = user.email
        }
        if let avatar: SetImageURL = try? await APIClient.shared.get("settings/avatar"),
           let urlString = avatar.url {
            avatarURL = URL(string: urlString)
        }
        if let signature: SetImageURL = try? await APIClient.shared.get("settings/signature"),
           let urlString = signature.url {
            signatureURL = URL(string: urlString)
        }
    }

    @MainActor
    func saveProfile() async {
        savedMessage = "Perfil atualizado com sucesso."
        struct Body: Encodable {
            let name: String
            let specialty: String
            let professionalRegistration: String
            let whatsapp: String
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.count >= 2 else {
            errorMessage = "O nome deve ter pelo menos 2 caracteres."
            showError = true
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let _: EmptyResponse = try await APIClient.shared.patch(
                "auth/me",
                body: Body(
                    name: trimmedName,
                    specialty: specialty.trimmingCharacters(in: .whitespacesAndNewlines),
                    professionalRegistration: registration.trimmingCharacters(in: .whitespacesAndNewlines),
                    whatsapp: PatientMask.whatsappPayload(whatsapp) ?? ""
                )
            )
            await SessionStore.shared.reloadProfile()
            showSaved = true
        } catch {
            present(error)
        }
    }

    /// Upload de foto (avatar/assinatura) escolhida na galeria.
    @MainActor
    func uploadImage(from item: PhotosPickerItem, kind: ImageKind) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.85)
        else {
            errorMessage = "Não foi possível ler a imagem escolhida."
            showError = true
            return
        }
        await upload(data: jpeg, fileName: "imagem.jpg", mimeType: "image/jpeg", kind: kind)
    }

    /// Upload do PNG desenhado no canvas de assinatura.
    @MainActor
    func uploadSignaturePNG(_ data: Data) async {
        await upload(data: data, fileName: "assinatura.png", mimeType: "image/png", kind: .signature)
    }

    @MainActor
    private func upload(data: Data, fileName: String, mimeType: String, kind: ImageKind) async {
        let path = kind == .avatar ? "settings/avatar" : "settings/signature"
        if kind == .avatar { isUploadingAvatar = true } else { isUploadingSignature = true }
        defer {
            if kind == .avatar { isUploadingAvatar = false } else { isUploadingSignature = false }
        }
        do {
            // Mesma chave de cache (o caminho não muda ao trocar o arquivo):
            // sem invalidar, a foto antiga continuaria aparecendo.
            if kind == .avatar { RemoteImageCache.shared.invalidar(avatarURL) }
            let response: SetImageURL = try await APIClient.shared.upload(
                path,
                fileData: data,
                fileName: fileName,
                mimeType: mimeType
            )
            let url = response.url.flatMap(URL.init(string:))
            if kind == .avatar { avatarURL = url } else { signatureURL = url }
        } catch {
            present(error)
        }
    }

    @MainActor
    private func present(_ error: Error) {
        errorMessage = (error as? APIError)?.message ?? "Não foi possível concluir. Verifique sua conexão."
        showError = true
    }
}
