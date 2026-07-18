import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Home de Arquivos: escolher paciente → anexos (substitui a placeholder)

struct FilesHomeView: View {
    @State private var selectedPatient: PFilePatientRef?
    @State private var patients: [PFilePatientRef] = []
    @State private var search = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    Text("Escolha o paciente pra ver e anexar arquivos.")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Theme.textSecondary)
                        TextField("Buscar paciente...", text: $search)
                            .font(Theme.body(15))
                            .autocorrectionDisabled()
                            .onSubmit { Task { await load() } }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 1))

                    if isLoading, patients.isEmpty {
                        ProgressView().padding(.top, 40)
                    } else if patients.isEmpty {
                        EmptyStateView(
                            icon: "folder",
                            title: "Nenhum paciente",
                            message: "Cadastre pacientes pra guardar exames, cartas e PDFs."
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(patients) { patient in
                                Button {
                                    selectedPatient = patient
                                } label: {
                                    HStack(spacing: 12) {
                                        InitialAvatar(name: patient.name, colorHex: patient.group?.color, size: 40)
                                        Text(patient.name)
                                            .font(Theme.body(15, weight: .semibold))
                                            .foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 14)
                                }
                                if patient.id != patients.last?.id {
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
                }
                .padding(Theme.screenPadding)
            }
        }
        .task { await load() }
        // Recarrega ao voltar da tela empurrada (.task não roda de novo).
        .onAppear {
            if hasAppeared {
                Task { await load() }
            }
            hasAppeared = true
        }
        .navigationDestination(item: $selectedPatient) { patient in
            PFilePatientFilesView(patient: patient)
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

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            patients = try await PFilesAPI.patients(search: search.isEmpty ? nil : search)
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível carregar os pacientes."
        }
    }
}

// MARK: - ViewModel dos anexos do paciente

@MainActor
@Observable
final class PFilePatientFilesViewModel {
    enum Filter: CaseIterable, Hashable {
        case all, exams, images, pdfs

        var label: String {
            switch self {
            case .all: "Tudo"
            case .exams: "Exames"
            case .images: "Imagens"
            case .pdfs: "PDFs"
            }
        }

        var category: PFileCategory? {
            switch self {
            case .all: nil
            case .exams: .exam
            case .images: .image
            case .pdfs: .pdf
            }
        }
    }

    let patient: PFilePatientRef
    var filter: Filter = .all
    var files: [PFileItem] = []
    var count = 0
    var totalSizeBytes = 0
    var isLoading = false
    var isUploading = false
    var errorMessage: String?
    var webLink: PFileWebLink?

    init(patient: PFilePatientRef) {
        self.patient = patient
    }

    var headerSubtitle: String {
        "\(count) arquivo\(count == 1 ? "" : "s") · \(PFileFormat.size(totalSizeBytes))"
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await PFilesAPI.list(patientId: patient.id, category: filter.category)
            files = response.files
            count = response.count
            totalSizeBytes = response.totalSizeBytes
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível carregar os arquivos."
        }
    }

    func setFilter(_ newFilter: Filter) {
        filter = newFilter
        Task { await load() }
    }

    func upload(data: Data, fileName: String, mimeType: String, category: PFileCategory?) async {
        isUploading = true
        defer { isUploading = false }
        do {
            _ = try await PFilesAPI.upload(
                patientId: patient.id,
                data: data,
                fileName: fileName,
                mimeType: mimeType,
                category: category
            )
            await load()
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível enviar o arquivo."
        }
    }

    func rename(_ file: PFileItem, to newName: String) async {
        do {
            _ = try await PFilesAPI.update(
                patientId: patient.id,
                id: file.id,
                body: PFileUpdateBody(fileName: newName, category: nil)
            )
            await load()
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível renomear o arquivo."
        }
    }

    func changeCategory(_ file: PFileItem, to category: PFileCategory) async {
        do {
            _ = try await PFilesAPI.update(
                patientId: patient.id,
                id: file.id,
                body: PFileUpdateBody(fileName: nil, category: category.rawValue)
            )
            await load()
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível mudar a categoria."
        }
    }

    func download(_ file: PFileItem) async {
        do {
            let response = try await PFilesAPI.downloadUrl(patientId: patient.id, id: file.id)
            if let url = URL(string: response.url) {
                webLink = PFileWebLink(url: url)
            }
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível baixar o arquivo."
        }
    }

    func remove(_ file: PFileItem) async {
        do {
            _ = try await PFilesAPI.remove(patientId: patient.id, id: file.id)
            await load()
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível excluir o arquivo."
        }
    }
}

/// Arquivo escolhido aguardando a categoria antes do upload.
private struct PFilePendingUpload {
    let data: Data
    let fileName: String
    let mimeType: String
}

// MARK: - Anexos do paciente (fiel aos prints, com empty state)

struct PFilePatientFilesView: View {
    @State private var model: PFilePatientFilesViewModel

    @State private var showAttachDialog = false
    @State private var showPhotosPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var pendingUpload: PFilePendingUpload?

    @State private var renamingFile: PFileItem?
    @State private var renameText = ""
    @State private var deletingFile: PFileItem?

    private static let documentTypes: [UTType] = [.pdf, .plainText]
        + [UTType(filenameExtension: "doc"), UTType(filenameExtension: "docx")].compactMap { $0 }

    init(patient: PFilePatientRef) {
        _model = State(initialValue: PFilePatientFilesViewModel(patient: patient))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    chips

                    if model.isLoading, model.files.isEmpty {
                        ProgressView().padding(.top, 40)
                    } else if model.files.isEmpty {
                        emptyState
                    } else {
                        fileList
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 90)
            }
            .refreshable { await model.load() }

            FloatingActionButton(icon: "paperclip") {
                showAttachDialog = true
            }
            .padding(.trailing, Theme.screenPadding)
            .padding(.bottom, 24)

            if model.isUploading {
                uploadOverlay
            }
        }
        .navigationTitle("Arquivos")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .confirmationDialog("Anexar arquivo", isPresented: $showAttachDialog, titleVisibility: .visible) {
            Button("Escolher da galeria") { showPhotosPicker = true }
            Button("Escolher PDF ou documento") { showFileImporter = true }
            Button("Cancelar", role: .cancel) {}
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $photoItem, matching: .images)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: Self.documentTypes
        ) { result in
            handleImportedFile(result)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await handlePickedPhoto(item) }
        }
        .confirmationDialog(
            "Categoria do anexo",
            isPresented: .init(
                get: { pendingUpload != nil },
                set: { if !$0 { pendingUpload = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Automática") { startUpload(category: nil) }
            ForEach(PFileCategory.allCases, id: \.self) { category in
                Button(category.label) { startUpload(category: category) }
            }
            Button("Cancelar", role: .cancel) { pendingUpload = nil }
        } message: {
            Text("Escolha como classificar o arquivo (opcional).")
        }
        .sheet(item: $model.webLink) { link in
            PFileSafariView(url: link.url).ignoresSafeArea()
        }
        .alert("Renomear arquivo", isPresented: .init(
            get: { renamingFile != nil },
            set: { if !$0 { renamingFile = nil } }
        )) {
            TextField("Nome do arquivo", text: $renameText)
            Button("Salvar") {
                if let file = renamingFile {
                    let name = renameText.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        Task { await model.rename(file, to: name) }
                    }
                }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Excluir arquivo?", isPresented: .init(
            get: { deletingFile != nil },
            set: { if !$0 { deletingFile = nil } }
        )) {
            Button("Excluir", role: .destructive) {
                if let file = deletingFile {
                    Task { await model.remove(file) }
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O arquivo será apagado. Essa ação não pode ser desfeita.")
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

    // MARK: Header e chips

    private var header: some View {
        HStack(spacing: 12) {
            InitialAvatar(name: model.patient.name, colorHex: model.patient.group?.color, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.patient.name)
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(model.count > 0 ? model.headerSubtitle : "Anexos do paciente")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(.top, 6)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PFilePatientFilesViewModel.Filter.allCases, id: \.self) { filter in
                    FilterChip(label: filter.label, isSelected: model.filter == filter) {
                        model.setFilter(filter)
                    }
                }
            }
        }
    }

    // MARK: Empty state fiel ao print

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.fill")
                .font(.system(size: 74))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: 0xEECF96), Color(hex: 0xDCAE62)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .padding(.top, 40)
            Text("Guarde aqui os arquivos\ndo seu paciente")
                .font(Theme.serifTitle(22))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text("Exames, cartas, PDFs, imagens — tudo em um lugar só,\nseguro e à mão quando precisar.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                showAttachDialog = true
            } label: {
                Label("Anexar arquivos", systemImage: "paperclip")
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 13)
                    .background(Theme.primary, in: Capsule())
                    .shadow(color: Theme.primary.opacity(0.35), radius: 10, y: 4)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Lista de arquivos

    private var fileList: some View {
        VStack(spacing: 0) {
            ForEach(model.files) { file in
                fileCell(file)
                if file.id != model.files.last?.id {
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

    private func fileCell(_ file: PFileItem) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(file.iconColors.background)
                .frame(width: 42, height: 42)
                .overlay(
                    Text(file.extensionLabel)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(file.iconColors.foreground)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(file.fileName)
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text("\(PFileFormat.size(file.sizeBytes)) · \(PFileFormat.relativeDay(file.createdAt))")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            fileMenu(file)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }

    private func fileMenu(_ file: PFileItem) -> some View {
        Menu {
            Button {
                Task { await model.download(file) }
            } label: {
                Label("Visualizar / baixar", systemImage: "arrow.down.circle")
            }
            Button {
                renameText = file.fileName
                renamingFile = file
            } label: {
                Label("Renomear", systemImage: "pencil")
            }
            Menu {
                ForEach(PFileCategory.allCases, id: \.self) { category in
                    Button {
                        Task { await model.changeCategory(file, to: category) }
                    } label: {
                        if category == file.category {
                            Label(category.label, systemImage: "checkmark")
                        } else {
                            Text(category.label)
                        }
                    }
                }
            } label: {
                Label("Mudar categoria", systemImage: "tag")
            }
            Button(role: .destructive) {
                deletingFile = file
            } label: {
                Label("Excluir", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 30, height: 34)
                .contentShape(Rectangle())
        }
    }

    private var uploadOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(Theme.primary)
                Text("Enviando arquivo...")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(26)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    // MARK: Seleção de arquivos

    private func handlePickedPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            model.errorMessage = "Não foi possível ler a imagem escolhida."
            return
        }
        let type = item.supportedContentTypes.first
        let ext = type?.preferredFilenameExtension ?? "jpg"
        let mime = type?.preferredMIMEType ?? "image/jpeg"
        let stamp = PFileFormat.dayMonth.string(from: Date()).replacingOccurrences(of: "/", with: "-")
        pendingUpload = PFilePendingUpload(
            data: data,
            fileName: "Foto \(stamp).\(ext)",
            mimeType: mime
        )
    }

    private func handleImportedFile(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                model.errorMessage = "Não foi possível ler o arquivo escolhido."
                return
            }
            let ext = url.pathExtension.lowercased()
            let mime: String = switch ext {
            case "pdf": "application/pdf"
            case "doc": "application/msword"
            case "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            case "txt": "text/plain"
            default: UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/pdf"
            }
            pendingUpload = PFilePendingUpload(data: data, fileName: url.lastPathComponent, mimeType: mime)
        case .failure:
            model.errorMessage = "Não foi possível importar o arquivo."
        }
    }

    private func startUpload(category: PFileCategory?) {
        guard let pending = pendingUpload else { return }
        pendingUpload = nil
        Task {
            await model.upload(
                data: pending.data,
                fileName: pending.fileName,
                mimeType: pending.mimeType,
                category: category
            )
        }
    }
}
