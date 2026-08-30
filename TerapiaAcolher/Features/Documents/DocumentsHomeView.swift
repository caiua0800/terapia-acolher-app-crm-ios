import SwiftUI

// MARK: - Documentos do paciente
//
// A tela-seletor que existia aqui (menu → lista de pacientes → documentos) foi
// removida em 2026-08-30: era uma segunda lista de pacientes. A entrada agora é
// a própria ficha do paciente, onde o dado sempre viveu (`/patients/{id}/documents`).
// MARK: - ViewModel dos documentos do paciente

@MainActor
@Observable
final class DocPatientDocumentsViewModel {
    let patient: DocPatientRef
    var documents: [DocItem] = []
    var isLoading = false
    var isWorking = false
    /// Documento com ação em voo — o spinner aparece na LINHA tocada, não
    /// numa barra genérica: é o toque que precisa responder.
    var workingDocumentId: String?
    var errorMessage: String?
    var webLink: DocWebLink?

    init(patient: DocPatientRef) {
        self.patient = patient
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            documents = try await DocumentsAPI.list(patientId: patient.id)
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível carregar os documentos."
        }
    }

    func open(_ document: DocItem) async {
        isWorking = true
        workingDocumentId = document.id
        defer { isWorking = false; workingDocumentId = nil }
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

    func sign(_ document: DocItem) async {
        isWorking = true
        workingDocumentId = document.id
        defer { isWorking = false; workingDocumentId = nil }
        do {
            _ = try await DocumentsAPI.sign(patientId: patient.id, id: document.id)
            await load()
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível assinar o documento."
        }
    }

    func remove(_ document: DocItem) async {
        isWorking = true
        workingDocumentId = document.id
        defer { isWorking = false; workingDocumentId = nil }
        do {
            _ = try await DocumentsAPI.remove(patientId: patient.id, id: document.id)
            await load()
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível excluir o documento."
        }
    }
}

// MARK: - Documentos do paciente (fiel ao print)

struct DocPatientDocumentsView: View {
    @State private var model: DocPatientDocumentsViewModel
    @State private var showGenerateFlow = false
    @State private var deletingDocument: DocItem?

    init(patient: DocPatientRef) {
        _model = State(initialValue: DocPatientDocumentsViewModel(patient: patient))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header

                    if model.isLoading, model.documents.isEmpty {
                        SkeletonList(linhas: 5, avatarSize: 44)
                    } else if model.documents.isEmpty {
                        EmptyStateView(
                            icon: "doc.text",
                            title: "Nenhum documento",
                            message: "Gere recibos, atestados e contratos a partir dos seus modelos."
                        )
                    } else {
                        documentList
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 110)
            }
            .refreshable { await model.load() }

            PrimaryButton(title: "Gerar novo documento", icon: "doc.badge.plus") {
                showGenerateFlow = true
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 16)
        }
        .navigationTitle("Documentos")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .sheet(isPresented: $showGenerateFlow) {
            DocGenerateFlowView(patient: model.patient) {
                Task { await model.load() }
            }
        }
        .sheet(item: $model.webLink) { link in
            DocSafariView(url: link.url).ignoresSafeArea()
        }
        .alert("Excluir documento?", isPresented: .init(
            get: { deletingDocument != nil },
            set: { if !$0 { deletingDocument = nil } }
        )) {
            Button("Excluir", role: .destructive) {
                if let document = deletingDocument {
                    Task { await model.remove(document) }
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O PDF será apagado. Essa ação não pode ser desfeita.")
        }
        .alert("Ops", isPresented: .init(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            InitialAvatar(name: model.patient.name, colorHex: model.patient.group?.color, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.patient.name)
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(model.documents.count) documento\(model.documents.count == 1 ? "" : "s") gerado\(model.documents.count == 1 ? "" : "s")")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(.top, 6)
    }

    private var documentList: some View {
        LazyVStack(spacing: 0) {
            ForEach(model.documents) { document in
                documentCell(document)
                if document.id != model.documents.last?.id {
                    Divider().overlay(Theme.border)
                }
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func documentCell(_ document: DocItem) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(DocVariables.purpleSoft)
                .frame(width: 42, height: 42)
                .overlay(
                    Text("PDF")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(DocVariables.purple)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(document.name)
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("Gerado \(DocFormat.relativeDay(document.createdAt))")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                    if document.isSigned {
                        StatusBadge(label: "ASSINADO", color: Theme.success, background: Theme.successSoft)
                    }
                }
            }
            Spacer(minLength: 8)
            AsyncIconButton(
                icon: "square.and.arrow.up",
                isLoading: model.workingDocumentId == document.id,
                isEnabled: model.workingDocumentId == nil,
                tint: Theme.textSecondary
            ) {
                Task { await model.open(document) }
            }
            .frame(width: 34, height: 34)
            documentMenu(document)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }

    private func documentMenu(_ document: DocItem) -> some View {
        Menu {
            Button {
                Task { await model.open(document) }
            } label: {
                Label("Visualizar PDF", systemImage: "eye")
            }
            if !document.isSigned {
                Button {
                    Task { await model.sign(document) }
                } label: {
                    Label("Assinar", systemImage: "signature")
                }
            }
            Button(role: .destructive) {
                deletingDocument = document
            } label: {
                Label("Excluir", systemImage: "trash")
            }
        } label: {
            // Ações do menu (assinar/excluir) também respondem no próprio
            // controle: o "···" vira spinner enquanto a requisição está em voo.
            ZStack {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .opacity(model.workingDocumentId == document.id ? 0 : 1)
                if model.workingDocumentId == document.id {
                    ProgressView().controlSize(.small).tint(Theme.textSecondary)
                }
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 26, height: 34)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.15), value: model.workingDocumentId)
        }
        .disabled(model.workingDocumentId != nil)
        .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
    }
}
