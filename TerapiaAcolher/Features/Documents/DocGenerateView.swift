import SwiftUI

// MARK: - Fluxo "Gerar novo documento": escolher modelo → variáveis → sucesso

struct DocGenerateFlowView: View {
    let patient: DocPatientRef
    var onGenerated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var templates: [DocTemplate] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Escolha um modelo pra começar. As variáveis são preenchidas na hora de gerar o PDF.")
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.textSecondary)

                        if isLoading, templates.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else if templates.isEmpty {
                            EmptyStateView(
                                icon: "doc.text",
                                title: "Nenhum modelo",
                                message: "Crie modelos de documento em Configurações → Modelos."
                            )
                        } else {
                            ForEach(templates) { template in
                                NavigationLink {
                                    DocGenerateView(patient: patient, template: template, onGenerated: onGenerated)
                                } label: {
                                    templateCell(template)
                                }
                            }
                        }
                    }
                    .padding(Theme.screenPadding)
                }
            }
            .navigationTitle("Selecionar modelo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .task { await load() }
            .alert("Ops", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func templateCell(_ template: DocTemplate) -> some View {
        ThemeCard {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(DocVariables.purpleSoft)
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "doc.text")
                            .font(.system(size: 17))
                            .foregroundStyle(DocVariables.purple)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(template.name)
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if template.isSystem {
                            StatusBadge(label: "SISTEMA", color: Theme.primary, background: Theme.primarySoft)
                        }
                    }
                    let extras = DocVariables.extraKeys(in: template.content)
                    Text(extras.isEmpty
                        ? "Variáveis preenchidas automaticamente"
                        : extras.map { "{\($0)}" }.joined(separator: " · "))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            templates = try await DocumentsAPI.templates()
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível carregar os modelos."
        }
    }
}

// MARK: - Tela de geração: prévia com variáveis roxas + campos extras

struct DocGenerateView: View {
    let patient: DocPatientRef
    let template: DocTemplate
    var onGenerated: () -> Void

    @Environment(\.dismiss) private var dismissSheet
    @State private var documentName: String
    @State private var extraValues: [String: String]
    @State private var isGenerating = false
    @State private var generated: DocItem?
    // Flags separadas: com um `isWorking` único, tocar em "Assinar" acendia o
    // spinner do botão "Visualizar PDF" — feedback no controle errado.
    @State private var isOpening = false
    @State private var isSigning = false
    @State private var webLink: DocWebLink?
    @State private var errorMessage: String?

    private let extraKeys: [String]

    init(patient: DocPatientRef, template: DocTemplate, onGenerated: @escaping () -> Void) {
        self.patient = patient
        self.template = template
        self.onGenerated = onGenerated
        let keys = DocVariables.extraKeys(in: template.content)
        extraKeys = keys
        _documentName = State(initialValue: template.name)
        _extraValues = State(initialValue: Dictionary(uniqueKeysWithValues: keys.map { ($0, "") }))
    }

    private var isValid: Bool {
        !documentName.trimmingCharacters(in: .whitespaces).isEmpty
            && extraKeys.allSatisfy { !(extraValues[$0] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let generated {
                successView(generated)
            } else {
                formView
            }
        }
        .navigationTitle(generated == nil ? "Novo documento" : "Documento gerado")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(generated != nil)
        .sheet(item: $webLink) { link in
            DocSafariView(url: link.url).ignoresSafeArea()
        }
        .alert("Ops", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Formulário

    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Text("Modelo: ")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                    + Text(template.name)
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(DocVariables.purple)
                    Spacer()
                    InitialAvatar(name: patient.name, size: 28)
                    Text(patient.name)
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                .padding(12)
                .background(DocVariables.purpleSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))

                fieldCard("Nome do documento") {
                    TextField("Ex.: Recibo · Sessões de julho", text: $documentName)
                        .font(Theme.body(15))
                }

                if !extraKeys.isEmpty {
                    ThemeCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("PREENCHA AS VARIÁVEIS")
                                .font(Theme.body(10, weight: .semibold))
                                .tracking(1.2)
                                .foregroundStyle(Theme.textSecondary)
                            ForEach(extraKeys, id: \.self) { key in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Text(DocVariables.label(for: key))
                                            .font(Theme.body(13, weight: .semibold))
                                            .foregroundStyle(Theme.textPrimary)
                                        Text("{\(key)}")
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(DocVariables.purple)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(DocVariables.purpleSoft, in: Capsule())
                                    }
                                    TextField(
                                        DocVariables.label(for: key),
                                        text: .init(
                                            get: { extraValues[key] ?? "" },
                                            set: { extraValues[key] = $0 }
                                        )
                                    )
                                    .font(Theme.body(15))
                                    .keyboardType(key == "valor" || key.contains("numero") ? .decimalPad : .default)
                                    .padding(10)
                                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                ThemeCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PRÉVIA DO MODELO")
                            .font(Theme.body(10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.textSecondary)
                        Text(DocVariables.highlighted(template.content))
                            .font(Theme.body(14))
                            .lineSpacing(5)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.success)
                    Text("Variáveis serão preenchidas ao gerar o PDF")
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(Theme.success)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.successSoft, in: RoundedRectangle(cornerRadius: 12))

                PrimaryButton(title: "Gerar documento", icon: "doc.badge.plus", isLoading: isGenerating, isEnabled: isValid) {
                    Task { await generate() }
                }
            }
            .padding(Theme.screenPadding)
        }
    }

    private func fieldCard(_ label: String, @ViewBuilder content: @escaping () -> some View) -> some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(label.uppercased())
                    .font(Theme.body(11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textSecondary)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Sucesso

    private func successView(_ document: DocItem) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Circle()
                    .fill(Theme.successSoft)
                    .frame(width: 84, height: 84)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Theme.success)
                    )
                    .padding(.top, 30)
                Text(document.name)
                    .font(Theme.serifTitle(22))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 6) {
                    Text("PDF gerado pra \(patient.name)")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                    if document.isSigned {
                        StatusBadge(label: "ASSINADO", color: Theme.success, background: Theme.successSoft)
                    }
                }

                VStack(spacing: 10) {
                    PrimaryButton(
                        title: "Visualizar PDF",
                        icon: "eye",
                        isLoading: isOpening,
                        isEnabled: !isSigning
                    ) {
                        Task { await open(document) }
                    }
                    if !document.isSigned {
                        SecondaryButton(
                            title: "Assinar documento",
                            icon: "signature",
                            isLoading: isSigning,
                            isEnabled: !isOpening,
                            tint: Theme.primary
                        ) {
                            Task { await sign(document) }
                        }
                    }
                    Button {
                        dismissSheet()
                    } label: {
                        Text("Concluir")
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .padding(.top, 10)
            }
            .padding(Theme.screenPadding)
        }
    }

    // MARK: Ações

    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }
        let variables = extraValues
            .mapValues { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.value.isEmpty }
        let body = DocGenerateBody(
            templateId: template.id,
            name: documentName.trimmingCharacters(in: .whitespaces),
            variables: variables.isEmpty ? nil : variables
        )
        do {
            generated = try await DocumentsAPI.generate(patientId: patient.id, body: body)
            onGenerated()
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível gerar o documento."
        }
    }

    private func open(_ document: DocItem) async {
        isOpening = true
        defer { isOpening = false }
        do {
            let response = try await DocumentsAPI.downloadUrl(patientId: patient.id, id: document.id)
            if let url = URL(string: response.url) {
                webLink = DocWebLink(url: url)
            }
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível abrir o documento."
        }
    }

    private func sign(_ document: DocItem) async {
        isSigning = true
        defer { isSigning = false }
        do {
            generated = try await DocumentsAPI.sign(patientId: patient.id, id: document.id)
            onGenerated()
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível assinar o documento."
        }
    }
}
