import Observation
import PhotosUI
import SwiftUI

/// Config · Meu perfil — capa com foto grande, selos de verificação, dados
/// profissionais, contato, assinatura, pendências e atalhos. Salvar/Descartar
/// só aparecem quando algo mudou. Mesma tela do web
/// (`web-app/app/(app)/configuracoes/perfil/perfil.tsx`).
struct SetProfileView: View {
    @State private var viewModel = SetProfileViewModel()
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var signaturePickerItem: PhotosPickerItem?
    @State private var showSignatureCanvas = false
    @State private var showLogoutConfirm = false
    @State private var showVerifyPhone = false
    @State private var profileStatus = ProfileStatusStore.shared

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    capa
                    pendencias
                    bloco("Dados profissionais", "Aparecem nos documentos que você gera e para a equipe da Terapia Acolher.") {
                        VStack(spacing: 12) {
                            campo("Nome completo", "Seu nome", $viewModel.name)
                            campo("Especialidade", "Ex.: Psicologia clínica", $viewModel.specialty)
                            campo("Registro profissional", "Ex.: CRP 06/54321", $viewModel.registration)
                        }
                    }
                    bloco("Contato", "Seu e-mail de acesso e o WhatsApp que recebe os avisos do CRM.") { contato }
                    bloco("Assinatura em documentos", "Vai nos PDFs gerados em Documentos: recibos, atestados e contratos.") { assinatura }
                    atalhos
                    sairButton
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, viewModel.alterado ? 96 : 24)
            }
        }
        .setToolbarTitle("Meu perfil")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if viewModel.alterado { barraDeSalvar }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.alterado)
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

    // MARK: - Capa

    private var emailVerificado: Bool { SessionStore.shared.user?.emailVerifiedAt != nil }
    private var numeroVerificado: Bool { profileStatus.status?.phoneVerifiedAt != nil }

    private var capa: some View {
        VStack(alignment: .leading, spacing: 0) {
            LinearGradient(
                colors: [Color(hex: 0xCFE3D3), Color(hex: 0xE7F0EA), Color(hex: 0xE2D9F3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 100)

            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    RemoteAvatar(
                        url: viewModel.avatarURL,
                        name: viewModel.name.isEmpty ? "?" : viewModel.name,
                        size: 108
                    )
                    .padding(5)
                    .background(Theme.surface, in: Circle())
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 5)

                    PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                        ZStack {
                            Circle().fill(Theme.primary).frame(width: 36, height: 36)
                            if viewModel.isUploadingAvatar {
                                ProgressView().tint(.white).controlSize(.small)
                            } else {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay(Circle().stroke(Theme.surface, lineWidth: 3))
                    }
                    .disabled(viewModel.isUploadingAvatar)
                    .accessibilityLabel("Trocar foto de perfil")
                    .offset(x: -4, y: -4)
                }
                .padding(.top, -58)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.name.isEmpty ? "Seu nome" : viewModel.name)
                        .font(Theme.serifTitle(25))
                        .foregroundStyle(Theme.textPrimary)
                    let sub = [viewModel.specialty, viewModel.registration].filter { !$0.isEmpty }.joined(separator: " · ")
                    Text(sub.isEmpty ? "Conte sua especialidade e seu registro profissional" : sub)
                        .font(Theme.body(13.5))
                        .foregroundStyle(Theme.textSecondary)
                }

                FlowLayout(spacing: 6) {
                    selo(emailVerificado, emailVerificado ? "E-mail verificado" : "E-mail não verificado")
                    if profileStatus.status?.whatsappEnabled == true {
                        selo(numeroVerificado, numeroVerificado ? "WhatsApp verificado" : "WhatsApp não verificado")
                    }
                }

                if viewModel.avatarURL == nil {
                    PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                        (Text("Uma foto sua deixa o CRM, os documentos e a Vitrine mais pessoais. ")
                            .foregroundStyle(Theme.textSecondary)
                         + Text("Enviar foto").fontWeight(.semibold).foregroundStyle(Theme.primary))
                            .font(Theme.body(12.5))
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border, lineWidth: 1))
    }

    private func selo(_ ok: Bool, _ texto: String) -> some View {
        Label(texto, systemImage: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            .font(Theme.body(11.5, weight: .semibold))
            .foregroundStyle(ok ? Theme.success : Theme.warning)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(ok ? Theme.successSoft : Theme.warningSoft, in: Capsule())
    }

    // MARK: - Pendências do perfil

    /// Repete no perfil o que o aviso do Início anuncia. É aqui que a pendência
    /// se resolve, então é aqui que ela precisa estar por escrito.
    @ViewBuilder
    private var pendencias: some View {
        if let status = profileStatus.status, status.temPendencia {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Falta pouco")
                        .font(Theme.body(14.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Resolva para aproveitar tudo do CRM.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.warningSoft)
                ForEach(Array(status.pendenciasVisiveis.enumerated()), id: \.element.id) { indice, item in
                    if indice > 0 { Divider().padding(.leading, 52) }
                    pendenciaRow(item)
                }
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.warning.opacity(0.35), lineWidth: 1))
        } else if profileStatus.status != nil {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.success, in: Circle())
                (Text("Perfil em dia. ").fontWeight(.semibold) + Text("Nada pendente por aqui."))
                    .font(Theme.body(13.5))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .padding(14)
            .background(Theme.successSoft, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
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
                    .font(Theme.body(14.5, weight: .semibold))
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
                Button {
                    Task { await viewModel.resendVerificationEmail() }
                } label: {
                    HStack(spacing: 5) {
                        if viewModel.isResendingEmail { ProgressView().controlSize(.mini) }
                        Text("Reenviar")
                    }
                }
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .disabled(viewModel.isResendingEmail)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Blocos

    private func bloco<C: View>(_ titulo: String, _ texto: String, @ViewBuilder _ conteudo: @escaping () -> C) -> some View {
        ThemeCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(titulo)
                        .font(Theme.serifTitle(18))
                        .foregroundStyle(Theme.textPrimary)
                    Text(texto)
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                conteudo()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func campo(_ rotulo: String, _ placeholder: String, _ texto: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rotulo)
                .font(Theme.body(12.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            TextField(placeholder, text: texto)
                .font(Theme.body(15))
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        }
    }

    private var contato: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("E-mail")
                    .font(Theme.body(12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 8) {
                    Image(systemName: "envelope").foregroundStyle(Theme.textSecondary)
                    Text(viewModel.email)
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                Text("É o seu login — não muda por aqui.")
                    .font(Theme.body(11.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                campo("WhatsApp", "+55 (11) 91234-5678", $viewModel.whatsapp)
                    .keyboardType(.phonePad)
                    // Mesma máscara do cadastro de paciente: o número do
                    // terapeuta ia cru para o banco e era a última porta por
                    // onde entrava telefone sem DDI.
                    .onChange(of: viewModel.whatsapp) { _, novo in
                        let m = PatientMask.whatsapp(novo)
                        if m != novo { viewModel.whatsapp = m }
                    }
                if profileStatus.status?.whatsappEnabled == true {
                    HStack(spacing: 8) {
                        if numeroVerificado {
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
        }
    }

    private var assinatura: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            .frame(height: 120)

            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    showSignatureCanvas = true
                } label: {
                    Label("Desenhar", systemImage: "signature")
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.primary, in: Capsule())
                }
                .buttonStyle(.pressable)
                PhotosPicker(selection: $signaturePickerItem, matching: .images) {
                    Label("Enviar imagem", systemImage: "photo")
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.primarySoft, in: Capsule())
                }
            }
        }
    }

    // MARK: - Atalhos

    private var atalhos: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ATALHOS")
                .font(Theme.body(11, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 4)
            atalho("Minha Vitrine", "Seu perfil público para pacientes", "sparkle.magnifyingglass") { VitrineView() }
            Divider().padding(.leading, 16)
            atalho("Mensagens aos pacientes", "Lembretes e cobranças por WhatsApp", "bubble.left.and.text.bubble.right") { SetMessagesView() }
            Divider().padding(.leading, 16)
            atalho("Meu consultório", "Endereço e duração das sessões", "building.2") { SetOfficeView() }
            Divider().padding(.leading, 16)
            atalho("Trocar senha", "Segurança da sua conta", "key") { SetChangePasswordView() }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.border, lineWidth: 1))
    }

    private func atalho<D: View>(_ titulo: String, _ texto: String, _ icone: String, @ViewBuilder destino: @escaping () -> D) -> some View {
        NavigationLink {
            destino()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icone)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 32, height: 32)
                    .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 1) {
                    Text(titulo)
                        .font(Theme.body(14.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(texto)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
    }

    // MARK: - Salvar / descartar

    private var barraDeSalvar: some View {
        HStack(spacing: 10) {
            Text("Alterações não salvas")
                .font(Theme.body(13.5))
                .foregroundStyle(.white)
            Spacer()
            Button("Descartar") {
                Haptics.tap()
                viewModel.descartar()
            }
            .font(Theme.body(13.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.75))
            .disabled(viewModel.isSaving)
            Button {
                Task { await viewModel.saveProfile() }
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isSaving { ProgressView().controlSize(.small).tint(Theme.ink) }
                    Text("Salvar")
                }
                .font(Theme.body(14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.white, in: Capsule())
            }
            .buttonStyle(.pressable)
            .disabled(viewModel.isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
        .padding(.horizontal, Theme.screenPadding)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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

    /// O que veio do servidor: base para "tem alteração?" e para Descartar.
    private var original = (name: "", specialty: "", registration: "", whatsapp: "")

    var alterado: Bool {
        !email.isEmpty
            && (name != original.name || specialty != original.specialty
                || registration != original.registration || whatsapp != original.whatsapp)
    }

    func descartar() {
        name = original.name
        specialty = original.specialty
        registration = original.registration
        whatsapp = original.whatsapp
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
            original = (name, specialty, registration, whatsapp)
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
            original = (name, specialty, registration, whatsapp)
            Haptics.success()
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
