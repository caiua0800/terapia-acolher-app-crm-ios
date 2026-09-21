import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ViewModel do assistente de abertura

@MainActor
@Observable
final class FinGatewayOnboardingModel {
    let fees: GwFees
    let provider: GwProvider
    let terms: GwTerms
    var account: GwAccount?

    var stepIndex = 0
    var errorMessage: String?

    // Etapa 1
    var personType: GwPersonType = .pf
    // Etapa 2
    var legalName = ""
    var cpfCnpj = ""
    var birthDate = ""
    var phone = ""
    var email = ""
    var incomeText = ""
    var companyType = "MEI"
    // Etapa 3
    var cep = ""
    var street = ""
    var number = ""
    var complement = ""
    var district = ""
    var city = ""
    var state = ""
    // Etapa 5
    var aceitouTermos = false
    var registrandoAceite = false

    /// Uma flag por ação (regra do projeto): o spinner acende só no controle
    /// tocado — nunca no botão errado.
    var isSavingStep = false
    var uploadingType: GwDocumentType?
    var removingDocumentId: String?
    var isSubmitting = false

    static let steps = [
        "Tipo de conta",
        "Dados",
        "Endereço",
        "Documentos",
        "Termos e envio",
    ]

    static let companyTypes: [(id: String, label: String)] = [
        ("MEI", "MEI"),
        ("LIMITED", "Sociedade limitada"),
        ("INDIVIDUAL", "Empresário individual"),
        ("ASSOCIATION", "Associação"),
    ]

    init(overview: GwOverview) {
        fees = overview.fees
        provider = overview.provider
        terms = overview.terms
        account = overview.account
        if let account = overview.account {
            personType = account.personType
            stepIndex = account.wizardStartIndex
            preencher(com: account)
        }
    }

    private func preencher(com account: GwAccount) {
        legalName = account.legalName ?? ""
        birthDate = GwFormat.typed(fromCalendarDay: account.birthDate)
        phone = account.phone.map(GwMask.phone) ?? ""
        email = account.email ?? ""
        incomeText = account.incomeValue.map { valor in
            valor == valor.rounded()
                ? String(Int(valor))
                : String(format: "%.2f", valor).replacingOccurrences(of: ".", with: ",")
        } ?? ""
        companyType = account.companyType ?? "MEI"
        if let address = account.address {
            cep = GwMask.cep(address.postalCode)
            street = address.street
            number = address.number
            complement = address.complement ?? ""
            district = address.district
            city = address.city
            state = address.state
        }
        aceitouTermos = account.termsAcceptedAt != nil
    }

    // MARK: Regras de habilitação

    var cpfCnpjJaGravado: Bool { account?.cpfCnpjMasked?.isEmpty == false }

    /// Documento válido pelo dígito verificador — contar dígitos deixava
    /// passar "111.111.111-11" e o cadastro voltava recusado dias depois.
    var documentoValido: Bool {
        // Já gravado no servidor: aqui só vem mascarado, não há o que validar.
        if cpfCnpjJaGravado && GwMask.digits(cpfCnpj).isEmpty { return true }
        return personType == .pf
            ? GwDocumentoValido.cpf(cpfCnpj)
            : GwDocumentoValido.cnpj(cpfCnpj)
    }

    /// Só reclama depois que o campo tem tamanho de documento — apontar erro
    /// no primeiro dígito digitado é ruído.
    var erroDoDocumento: String? {
        let digitos = GwMask.digits(cpfCnpj)
        let esperado = personType == .pf ? 11 : 14
        guard digitos.count == esperado, !documentoValido else { return nil }
        return "\(personType.documentLabel) inválido — confira os números."
    }

    var podeAvancarDados: Bool {
        let documentoOk = documentoValido
        let nascimentoOk = personType == .pj || GwFormat.calendarDay(fromTyped: birthDate) != nil
        return legalName.trimmingCharacters(in: .whitespaces).count >= 3
            && documentoOk
            && nascimentoOk
            && GwMask.digits(phone).count >= 10
            && email.contains("@")
    }

    var podeAvancarEndereco: Bool {
        GwMask.digits(cep).count == 8
            && street.trimmingCharacters(in: .whitespaces).count >= 2
            && !number.trimmingCharacters(in: .whitespaces).isEmpty
            && district.trimmingCharacters(in: .whitespaces).count >= 2
            && city.trimmingCharacters(in: .whitespaces).count >= 2
            && state.trimmingCharacters(in: .whitespaces).count == 2
    }

    var documentosPendentes: [GwDocumentType] { account?.missingDocuments ?? [] }

    var documentosPedidos: [GwDocumentType] {
        account?.requiredDocuments ?? [.identityFront, .identityBack, .selfie]
    }

    var aceiteRegistrado: Bool { account?.termsAcceptedAt != nil }

    var podeEnviarParaAnalise: Bool {
        aceitouTermos && documentosPendentes.isEmpty && account != nil
    }

    // MARK: Ações por etapa

    func avancar() async -> Bool {
        errorMessage = nil
        switch stepIndex {
        case 0: return await salvarTipo()
        case 1: return await salvarDados()
        case 2: return await salvarEndereco()
        case 3:
            guard documentosPendentes.isEmpty else {
                errorMessage = "Falta enviar: "
                    + documentosPendentes.map(\.label).joined(separator: ", ") + "."
                return false
            }
            return true
        default: return true
        }
    }

    private func salvarTipo() async -> Bool {
        if let account, account.personType == personType, account.status == .draft {
            return true
        }
        return await executar { [personType] in
            try await FinGatewayAPI.start(personType: personType)
        }
    }

    private func salvarDados() async -> Bool {
        let body = GwPersonalBody(
            legalName: legalName.trimmingCharacters(in: .whitespaces),
            cpfCnpj: GwMask.digits(cpfCnpj),
            birthDate: personType == .pf ? GwFormat.calendarDay(fromTyped: birthDate) : nil,
            phone: GwMask.digits(phone),
            email: email.trimmingCharacters(in: .whitespaces).lowercased(),
            incomeValue: GwMask.amount(incomeText),
            companyType: personType == .pj ? companyType : nil
        )
        return await executar { try await FinGatewayAPI.savePersonal(body) }
    }

    private func salvarEndereco() async -> Bool {
        let body = GwAddressBody(
            postalCode: GwMask.digits(cep),
            street: street.trimmingCharacters(in: .whitespaces),
            number: number.trimmingCharacters(in: .whitespaces),
            complement: complement.isEmpty ? nil : complement,
            district: district.trimmingCharacters(in: .whitespaces),
            city: city.trimmingCharacters(in: .whitespaces),
            state: state.uppercased()
        )
        return await executar { try await FinGatewayAPI.saveAddress(body) }
    }

    /// Grava o aceite no instante do toque, como no web.
    ///
    /// Antes ele só era enviado junto do `submit()`: se o envio falhasse, o
    /// terapeuta tinha marcado o aceite e o servidor não tinha registro nenhum
    /// disso — justamente o documento que precisa ficar guardado.
    @MainActor
    func registrarAceite() async {
        guard aceitouTermos, account?.termsAcceptedAt == nil, !registrandoAceite else { return }
        registrandoAceite = true
        defer { registrandoAceite = false }
        do {
            let atualizada = try await FinGatewayAPI.acceptTerms(version: terms.version)
            account = atualizada
            FinGatewayStore.shared.apply(atualizada)
        } catch {
            // Silencioso: o envio para análise tenta de novo antes de submeter.
        }
    }

    func enviarParaAnalise() async -> Bool {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            if account?.termsAcceptedAt == nil {
                account = try await FinGatewayAPI.acceptTerms(version: terms.version)
            }
            let enviada = try await FinGatewayAPI.submit()
            account = enviada
            FinGatewayStore.shared.apply(enviada)
            Haptics.success()
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = (error as? APIError)?.message
                ?? "Não foi possível enviar para análise."
            Haptics.warning()
            return false
        }
    }

    private func executar(_ operation: () async throws -> GwAccount) async -> Bool {
        isSavingStep = true
        defer { isSavingStep = false }
        do {
            let atualizada = try await operation()
            account = atualizada
            FinGatewayStore.shared.apply(atualizada)
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = (error as? APIError)?.message
                ?? "Não foi possível salvar esta etapa."
            Haptics.warning()
            return false
        }
    }

    // MARK: Documentos

    func enviarDocumento(
        _ type: GwDocumentType,
        data: Data,
        fileName: String,
        mimeType: String,
        captureMode: String,
        livenessScore: Double?
    ) async {
        errorMessage = nil
        uploadingType = type
        defer { uploadingType = nil }
        do {
            _ = try await FinGatewayAPI.uploadDocument(
                data: data,
                fileName: fileName,
                mimeType: mimeType,
                type: type,
                captureMode: captureMode,
                livenessScore: livenessScore
            )
            await recarregar()
            Haptics.success()
        } catch is CancellationError {
            // cancelado — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message
                ?? "Não foi possível enviar o documento."
            Haptics.warning()
        }
    }

    func enviarFotos(_ imagens: [UIImage], type: GwDocumentType, aoVivo: Bool) async {
        guard let ultima = imagens.last,
              let data = GwImage.downscaledJPEG(ultima)
        else {
            errorMessage = "Não foi possível ler a foto. Tente de novo."
            return
        }
        let score = imagens.count >= 2
            ? GwLiveness.score(first: imagens[0], second: imagens[1])
            : nil
        await enviarDocumento(
            type,
            data: data,
            fileName: "\(type.rawValue.lowercased()).jpg",
            mimeType: "image/jpeg",
            captureMode: aoVivo ? "live" : "upload",
            livenessScore: score
        )
    }

    func removerDocumento(_ document: GwDocument) async {
        removingDocumentId = document.id
        defer { removingDocumentId = nil }
        do {
            _ = try await FinGatewayAPI.deleteDocument(id: document.id)
            await recarregar()
        } catch is CancellationError {
        } catch {
            errorMessage = (error as? APIError)?.message
                ?? "Não foi possível remover o documento."
        }
    }

    func recarregar() async {
        await FinGatewayStore.shared.load(showSpinner: false)
        if let atual = FinGatewayStore.shared.account {
            account = atual
        }
    }
}

// MARK: - Assistente em 5 etapas (padrão do wizard de paciente)

struct FinGatewayOnboardingView: View {
    @State private var model: FinGatewayOnboardingModel
    @Environment(\.dismiss) private var dismiss

    /// Documento aguardando origem (câmera ou galeria).
    @State private var escolhendoOrigem: GwDocumentType?
    @State private var removendo: GwDocument?
    @State private var capturando: GwDocumentType?
    @State private var galeriaPara: GwDocumentType?
    @State private var mostrandoGaleria = false
    @State private var fotoSelecionada: PhotosPickerItem?
    @State private var pdfPara: GwDocumentType?
    @State private var importandoPDF = false
    @State private var enviadaComSucesso = false

    init(overview: GwOverview) {
        _model = State(initialValue: FinGatewayOnboardingModel(overview: overview))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    progressHeader
                    ScrollView {
                        VStack(spacing: 16) {
                            stepContent
                            if let error = model.errorMessage {
                                erroInline(error)
                            }
                            GwProviderFooter(provider: model.provider)
                        }
                        .padding(.horizontal, Theme.screenPadding)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                    footer
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if model.stepIndex > 0 {
                            withAnimation { model.stepIndex -= 1 }
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: model.stepIndex > 0 ? "arrow.left" : "xmark")
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Ativar recebimentos")
                        .font(Theme.serifTitle(19))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .interactiveDismissDisabled(model.isSavingStep || model.isSubmitting)
            .alert("Remover documento?", isPresented: .init(
                get: { removendo != nil },
                set: { if !$0 { removendo = nil } }
            )) {
                Button("Remover", role: .destructive) {
                    if let documento = removendo {
                        Task { await model.removerDocumento(documento) }
                    }
                }
                Button("Voltar", role: .cancel) {}
            } message: {
                Text("O arquivo sai do cadastro e você precisa enviar outro no lugar.")
            }
            .confirmationDialog(
                "Enviar documento",
                isPresented: .init(
                    get: { escolhendoOrigem != nil },
                    set: { if !$0 { escolhendoOrigem = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let tipo = escolhendoOrigem {
                    if FinGatewayCameraView.isAvailable {
                        Button("Tirar foto agora") { capturando = tipo }
                    }
                    // Selfie não aceita galeria: é ela que comprova que a
                    // pessoa está aqui agora. Foto salva serve para qualquer um.
                    if tipo != .selfie {
                        Button("Escolher da galeria") {
                            galeriaPara = tipo
                            mostrandoGaleria = true
                        }
                    }
                    if tipo.acceptsPDF {
                        Button("Escolher um PDF") {
                            pdfPara = tipo
                            importandoPDF = true
                        }
                    }
                    Button("Cancelar", role: .cancel) {}
                }
            } message: {
                if escolhendoOrigem == .selfie, !FinGatewayCameraView.isAvailable {
                    Text("A selfie só pode ser tirada pela câmera — este aparelho não tem uma disponível. Conclua a abertura pelo site.")
                } else {
                    Text(escolhendoOrigem?.hint ?? "")
                }
            }
            .fullScreenCover(item: $capturando) { tipo in
                FinGatewayCameraView(
                    modo: tipo == .selfie ? .selfie : .documento,
                    titulo: tipo.label,
                    onCapture: { imagens in
                        capturando = nil
                        Task { await model.enviarFotos(imagens, type: tipo, aoVivo: true) }
                    },
                    onCancel: { capturando = nil }
                )
                .ignoresSafeArea()
            }
            // `isPresented` precisa ser um Bool próprio: amarrado a
            // `galeriaPara != nil`, o fechamento do seletor zerava o tipo do
            // documento ANTES do onChange da seleção — a foto era escolhida e
            // nada era enviado.
            .photosPicker(
                isPresented: $mostrandoGaleria,
                selection: $fotoSelecionada,
                matching: .images
            )
            .onChange(of: fotoSelecionada) { _, item in
                guard let item, let tipo = galeriaPara else { return }
                galeriaPara = nil
                fotoSelecionada = nil
                Task { await enviarDaGaleria(item, tipo: tipo) }
            }
            .fileImporter(isPresented: $importandoPDF, allowedContentTypes: [.pdf]) { resultado in
                let tipo = pdfPara ?? .socialContract
                pdfPara = nil
                importarPDF(resultado, tipo: tipo)
            }
            .alert("Conta enviada para análise", isPresented: $enviadaComSucesso) {
                Button("Fechar") { dismiss() }
            } message: {
                Text("Assim que a análise terminar você recebe um aviso aqui no app.")
            }
        }
    }

    // MARK: Progresso

    private var progressHeader: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(Array(FinGatewayOnboardingModel.steps.enumerated()), id: \.offset) { index, _ in
                    Circle()
                        .fill(index <= model.stepIndex ? Theme.primary : Theme.border)
                        .frame(width: 8, height: 8)
                }
            }
            Spacer()
            Text("\(model.stepIndex + 1) de 5 · \(FinGatewayOnboardingModel.steps[model.stepIndex])")
                .font(Theme.body(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 12)
    }

    private func erroInline(_ mensagem: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
            Text(mensagem)
                .font(Theme.body(13, weight: .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.danger)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("gwErro")
    }

    // MARK: Conteúdo por etapa

    @ViewBuilder
    private var stepContent: some View {
        switch model.stepIndex {
        case 0: etapaTipo
        case 1: etapaDados
        case 2: etapaEndereco
        case 3: etapaDocumentos
        default: etapaTermos
        }
    }

    // Etapa 1 — tipo

    private var etapaTipo: some View {
        VStack(spacing: 12) {
            Text("Você recebe como pessoa física ou pelo CNPJ do seu consultório?")
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            GwChoiceCard(
                icon: "person",
                title: "Pessoa física",
                subtitle: "Recebo no meu CPF",
                isSelected: model.personType == .pf
            ) { model.personType = .pf }
            GwChoiceCard(
                icon: "building.2",
                title: "Pessoa jurídica",
                subtitle: "Recebo no CNPJ (MEI ou empresa)",
                isSelected: model.personType == .pj
            ) { model.personType = .pj }
            GwFeesCard(fees: model.fees, provider: model.provider)
        }
    }

    // Etapa 2 — dados

    private var etapaDados: some View {
        PatientFormSection(
            icon: "person.text.rectangle",
            title: model.personType == .pf ? "SEUS DADOS" : "DADOS DA EMPRESA"
        ) {
            VStack(spacing: 14) {
                GwField(label: model.personType == .pf ? "Nome completo" : "Razão social") {
                    TextField("Como está no documento", text: $model.legalName)
                        .textContentType(.name)
                        .accessibilityIdentifier("gwLegalName")
                }
                GwField(
                    label: model.personType.documentLabel,
                    hint: model.cpfCnpjJaGravado
                        ? "Guardado: \(model.account?.cpfCnpjMasked ?? "") — digite de novo para confirmar."
                        : nil,
                    erro: model.erroDoDocumento
                ) {
                    TextField(
                        model.personType == .pf ? "000.000.000-00" : "00.000.000/0000-00",
                        text: $model.cpfCnpj
                    )
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("gwCpfCnpj")
                    .onChange(of: model.cpfCnpj) { _, novo in
                        let mascarado = GwMask.document(novo, personType: model.personType)
                        if mascarado != novo { model.cpfCnpj = mascarado }
                    }
                }
                if model.personType == .pf {
                    GwField(label: "Data de nascimento") {
                        TextField("00/00/0000", text: $model.birthDate)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("gwBirthDate")
                            .onChange(of: model.birthDate) { _, novo in
                                let mascarado = GwMask.date(novo)
                                if mascarado != novo { model.birthDate = mascarado }
                            }
                    }
                } else {
                    GwField(label: "Tipo da empresa") {
                        Picker("", selection: $model.companyType) {
                            ForEach(FinGatewayOnboardingModel.companyTypes, id: \.id) { tipo in
                                Text(tipo.label).tag(tipo.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                GwField(label: "Telefone") {
                    TextField("+55 (11) 99999-9999", text: $model.phone)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("gwPhone")
                        .onChange(of: model.phone) { _, novo in
                            let mascarado = GwMask.phone(novo)
                            if mascarado != novo { model.phone = mascarado }
                        }
                }
                GwField(label: "E-mail") {
                    TextField("voce@email.com", text: $model.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("gwEmail")
                }
                GwField(
                    label: "Renda mensal aproximada",
                    hint: "Informação exigida pelo \(model.provider.name), a instituição de pagamento que opera a conta."
                ) {
                    TextField("3.000", text: $model.incomeText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("gwIncome")
                }
            }
        }
    }

    // Etapa 3 — endereço

    private var etapaEndereco: some View {
        PatientFormSection(icon: "mappin.and.ellipse", title: "ENDEREÇO") {
            VStack(spacing: 14) {
                GwField(label: "CEP") {
                    TextField("00000-000", text: $model.cep)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("gwCep")
                        .onChange(of: model.cep) { _, novo in
                            let mascarado = GwMask.cep(novo)
                            if mascarado != novo { model.cep = mascarado }
                        }
                }
                GwField(label: "Rua") {
                    TextField("Av. Paulista", text: $model.street)
                        .accessibilityIdentifier("gwStreet")
                }
                HStack(spacing: 12) {
                    GwField(label: "Número") {
                        TextField("1000", text: $model.number)
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityIdentifier("gwNumber")
                    }
                    GwField(label: "Complemento") {
                        TextField("Sala 12", text: $model.complement)
                            .accessibilityIdentifier("gwComplement")
                    }
                }
                GwField(label: "Bairro") {
                    TextField("Bela Vista", text: $model.district)
                        .accessibilityIdentifier("gwDistrict")
                }
                HStack(spacing: 12) {
                    GwField(label: "Cidade") {
                        TextField("São Paulo", text: $model.city)
                            .accessibilityIdentifier("gwCity")
                    }
                    GwField(label: "UF") {
                        Picker("UF", selection: $model.state) {
                            Text("—").tag("")
                            ForEach(GwUF.todas, id: \.self) { uf in
                                Text(uf).tag(uf)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(Theme.textPrimary)
                        .accessibilityIdentifier("gwState")
                    }
                    .frame(width: 100)
                }
            }
        }
    }

    // Etapa 4 — documentos

    private var etapaDocumentos: some View {
        VStack(spacing: 12) {
            Text(FinGatewayCameraView.isAvailable
                ? "O \(model.provider.name), instituição de pagamento que opera a conta, precisa conferir quem está abrindo ela. Tire as fotos com boa luz — elas vão criptografadas e só são vistas pela análise."
                : "Este aparelho não tem câmera disponível — escolha as imagens da galeria. Elas vão criptografadas para a análise do \(model.provider.name).")
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(model.documentosPedidos, id: \.self) { tipo in
                documentoCard(tipo)
            }
        }
    }

    private func documentoCard(_ tipo: GwDocumentType) -> some View {
        let documento = model.account?.document(tipo)
        return ThemeCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Theme.primarySoft)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: tipo.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.primary)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tipo.label)
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(tipo.hint)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    if let documento {
                        StatusBadge.gwDocument(documento.status)
                    }
                }

                if let documento {
                    HStack(alignment: .top, spacing: 12) {
                        if let url = documento.previewURL {
                            AsyncImage(url: url) { fase in
                                switch fase {
                                case let .success(imagem):
                                    imagem.resizable().scaledToFill()
                                case .failure:
                                    Image(systemName: "doc")
                                        .foregroundStyle(Theme.textSecondary)
                                default:
                                    ProgressView().controlSize(.small)
                                }
                            }
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            if let capturedAt = documento.capturedAt {
                                Text("Enviado em \(GwFormat.shortDayTime.string(from: capturedAt))")
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            if documento.captureMode == "live" {
                                Label("Capturado ao vivo", systemImage: "camera.viewfinder")
                                    .font(Theme.body(11, weight: .semibold))
                                    .foregroundStyle(Theme.success)
                            }
                            if let motivo = documento.rejectionReason, !motivo.isEmpty {
                                Text(motivo)
                                    .font(Theme.body(12, weight: .medium))
                                    .foregroundStyle(Theme.danger)
                            }
                        }
                        Spacer(minLength: 0)

                        // Remover existia no model e não tinha botão: mandar a
                        // foto errada só dava para "enviar de novo", e a errada
                        // continuava no cadastro.
                        Button {
                            Haptics.tap()
                            removendo = documento
                        } label: {
                            if model.removingDocumentId == documento.id {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.danger)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(model.removingDocumentId != nil)
                        .accessibilityLabel("Remover \(documento.title)")
                    }
                }

                SecondaryButton(
                    title: documento == nil ? "Enviar \(tipo.label.lowercased())" : "Enviar de novo",
                    icon: FinGatewayCameraView.isAvailable ? "camera" : "photo",
                    isLoading: model.uploadingType == tipo,
                    isEnabled: model.uploadingType == nil,
                    tint: Theme.primary
                ) {
                    escolhendoOrigem = tipo
                }
                .accessibilityIdentifier("gwEnviar-\(tipo.rawValue)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Etapa 5 — termos

    private var etapaTermos: some View {
        VStack(spacing: 14) {
            GwFeesCard(fees: model.fees, provider: model.provider)

            PatientFormSection(icon: "doc.text", title: "CONDIÇÕES DO SERVIÇO") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.terms.clause)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                    Divider().overlay(Theme.border)
                    Toggle(isOn: $model.aceitouTermos) {
                        Text("Li e aceito a cláusula acima e autorizo a abertura da conta de pagamento no \(model.provider.name).")
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.primary)
                    .accessibilityIdentifier("gwAceite")
                    .onChange(of: model.aceitouTermos) { _, _ in
                        Task { await model.registrarAceite() }
                    }

                    HStack(spacing: 6) {
                        if model.registrandoAceite {
                            ProgressView().controlSize(.small).tint(Theme.textSecondary)
                        } else if model.aceiteRegistrado {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.success)
                        }
                        Text(model.aceiteRegistrado
                             ? "Versão \(model.terms.version) · aceite registrado"
                             : "Versão \(model.terms.version)")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            PatientFormSection(icon: "checklist", title: "CONFERÊNCIA") {
                VStack(alignment: .leading, spacing: 10) {
                    conferenciaLinha("Dados pessoais", ok: model.cpfCnpjJaGravado || model.podeAvancarDados)
                    conferenciaLinha("Endereço", ok: model.podeAvancarEndereco)
                    conferenciaLinha(
                        "Documentos (\(model.documentosPedidos.count - model.documentosPendentes.count) de \(model.documentosPedidos.count))",
                        ok: model.documentosPendentes.isEmpty
                    )
                    conferenciaLinha("Aceite das condições", ok: model.aceiteRegistrado)
                }
            }

            if !model.documentosPendentes.isEmpty {
                erroInline(
                    "Falta enviar: "
                        + model.documentosPendentes.map(\.label).joined(separator: ", ") + "."
                )
            }
        }
    }

    private func conferenciaLinha(_ titulo: String, ok: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(ok ? Theme.success : Theme.textSecondary.opacity(0.5))
            Text(titulo)
                .font(Theme.body(14))
                .foregroundStyle(ok ? Theme.textPrimary : Theme.textSecondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: Rodapé

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.border)
            if model.stepIndex < 4 {
                PrimaryButton(
                    title: "Continuar",
                    isLoading: model.isSavingStep,
                    isEnabled: podeContinuar
                ) {
                    Task {
                        if await model.avancar() {
                            withAnimation { model.stepIndex += 1 }
                        }
                    }
                }
                .padding(Theme.screenPadding)
            } else {
                PrimaryButton(
                    title: "Enviar para análise",
                    icon: "paperplane",
                    isLoading: model.isSubmitting,
                    isEnabled: model.podeEnviarParaAnalise
                ) {
                    Task {
                        if await model.enviarParaAnalise() { enviadaComSucesso = true }
                    }
                }
                .padding(Theme.screenPadding)
            }
        }
        .background(Theme.background)
    }

    private var podeContinuar: Bool {
        switch model.stepIndex {
        case 1: model.podeAvancarDados
        case 2: model.podeAvancarEndereco
        default: true
        }
    }

    // MARK: Origens de arquivo

    private func enviarDaGaleria(_ item: PhotosPickerItem, tipo: GwDocumentType) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let imagem = UIImage(data: data)
        else {
            model.errorMessage = "Não foi possível ler a imagem escolhida. Tente outra."
            return
        }
        await model.enviarFotos([imagem], type: tipo, aoVivo: false)
    }

    private func importarPDF(_ resultado: Result<URL, Error>, tipo: GwDocumentType) {
        switch resultado {
        case let .success(url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                model.errorMessage = "Não foi possível ler o arquivo escolhido."
                return
            }
            Task {
                await model.enviarDocumento(
                    tipo,
                    data: data,
                    fileName: url.lastPathComponent,
                    mimeType: "application/pdf",
                    captureMode: "upload",
                    livenessScore: nil
                )
            }
        case .failure:
            model.errorMessage = "Não foi possível importar o arquivo."
        }
    }
}

extension GwDocumentType: Identifiable {
    var id: String { rawValue }
}
