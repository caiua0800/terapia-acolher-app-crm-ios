import SwiftUI

/// Ficha do lead: tudo que o quiz capturou, mudança de status e conversão em
/// paciente. O lead vem do sistema de leads via CRM; o status e a conversão
/// são gravados no CRM (ver LeadsStore).
struct LeadDetailView: View {
    let leadId: String

    @State private var store = LeadsStore.shared
    @State private var showConvert = false
    @State private var showConverted = false
    @Environment(\.openURL) private var openURL

    private var lead: Lead? { store.lead(id: leadId) }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let lead {
                content(lead)
            } else if store.isLoading {
                ProgressView().tint(Theme.primary)
            } else {
                EmptyStateView(
                    icon: "tray",
                    title: "Lead não encontrado",
                    message: "Ele pode ter sido removido da sua lista."
                )
            }
        }
        .setToolbarTitle("Lead")
        .navigationBarTitleDisplayMode(.inline)
        // Chegou por link direto, sem passar pela lista: carrega.
        .task { if store.connection == nil { await store.load() } }
        .alert("Ops", isPresented: $store.showAlerta) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.alerta ?? "Algo deu errado.")
        }
        .sheet(isPresented: $showConvert) {
            if let lead {
                PatientFormView(
                    mode: .fromLead(name: lead.name, whatsapp: lead.whatsapp)
                ) { paciente in
                    Task { await store.markConverted(lead.id, patientId: paciente.id) }
                    showConverted = true
                }
            }
        }
        .alert("Virou paciente!", isPresented: $showConverted) {
            Button("Fechar", role: .cancel) {}
        } message: {
            Text("O lead foi marcado como agendado e agora tem ficha completa em Pacientes.")
        }
    }

    private func content(_ lead: Lead) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(lead)
                actions(lead)
                statusCard(lead)
                quizCard(lead)
                if lead.therapyFor == .infantil || lead.therapyFor == .outraPessoa {
                    dependentCard(lead)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 10)
            .padding(.bottom, 32)
        }
    }

    // MARK: Cabeçalho

    private func header(_ lead: Lead) -> some View {
        VStack(spacing: 10) {
            InitialAvatar(name: lead.name, colorHex: nil, size: 76)
            Text(lead.name)
                .font(Theme.serifTitle(24))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                let (cor, fundo) = LeadStyle.colors(for: lead.status)
                StatusBadge(label: lead.status.shortLabel, color: cor, background: fundo)
                Text("chegou \(lead.elapsedLabel)")
                    .font(Theme.body(13))
                    .foregroundStyle(lead.sla == .late ? Theme.danger : Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    // MARK: Ações

    private func actions(_ lead: Lead) -> some View {
        VStack(spacing: 10) {
            if lead.whatsapp.isEmpty {
                Text("Este lead chegou sem número de WhatsApp.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                Button {
                    Haptics.tap()
                    abrirWhatsApp(lead)
                } label: {
                    Label("Chamar no WhatsApp", systemImage: "bubble.left.fill")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.primary, in: Capsule())
                }
                .buttonStyle(.pressable)
            }

            if lead.convertedPatientId == nil {
                Button {
                    Haptics.tap()
                    showConvert = true
                } label: {
                    Label("Transformar em paciente", systemImage: "person.badge.plus")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.primarySoft, in: Capsule())
                }
                .buttonStyle(.pressable)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.success)
                    Text("Já é seu paciente")
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
                .padding(.vertical, 13)
                .padding(.horizontal, 16)
                .background(Theme.successSoft, in: Capsule())
            }
        }
    }

    /// Abre a conversa já com uma primeira mensagem escrita — o atrito de
    /// "o que eu escrevo?" é o que mais adia o primeiro contato.
    private func abrirWhatsApp(_ lead: Lead) {
        let digits = lead.whatsapp.filter(\.isNumber)
        let texto = "Olá, \(lead.primeiroNome)! Aqui é da Terapia Acolher. Vi que você procura atendimento e queria entender melhor como posso te ajudar."
        let encoded = texto.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://wa.me/\(digits)?text=\(encoded)") {
            openURL(url)
        }
    }

    // MARK: Status

    private func statusCard(_ lead: Lead) -> some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("EM QUE PÉ ESTÁ")
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)

                ForEach(LeadStatus.allCases) { opcao in
                    statusRow(opcao, atual: lead.status)
                    if opcao != LeadStatus.allCases.last {
                        Divider().overlay(Theme.border)
                    }
                }
            }
        }
    }

    private func statusRow(_ opcao: LeadStatus, atual: LeadStatus) -> some View {
        let selecionado = opcao == atual
        let (cor, fundo) = LeadStyle.colors(for: opcao)
        return Button {
            guard !selecionado else { return }
            Haptics.success()
            withAnimation(.easeInOut(duration: 0.2)) {
                Task { await store.updateStatus(leadId, to: opcao) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: opcao.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(cor)
                    .frame(width: 32, height: 32)
                    .background(fundo, in: RoundedRectangle(cornerRadius: 9))
                Text(opcao.label)
                    .font(Theme.body(15, weight: selecionado ? .semibold : .regular))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if selecionado {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
    }

    // MARK: O que o quiz capturou

    private func quizCard(_ lead: Lead) -> some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("O QUE ELE CONTOU")
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 12)

                infoRow("Buscando", lead.reason, destaque: true)
                Divider().overlay(Theme.border).padding(.vertical, 10)
                infoRow("Terapia para", lead.therapyFor.label)
                Divider().overlay(Theme.border).padding(.vertical, 10)
                infoRow("WhatsApp", lead.whatsappLegivel)
                Divider().overlay(Theme.border).padding(.vertical, 10)
                infoRow("Melhor horário", lead.shift.label)
                Divider().overlay(Theme.border).padding(.vertical, 10)
                infoRow("Quando chamar", lead.contactWhen)
                Divider().overlay(Theme.border).padding(.vertical, 10)
                infoRow("Se identifica como", lead.gender.label)
                Divider().overlay(Theme.border).padding(.vertical, 10)
                infoRow("Prefere", lead.preferredTherapistLabel)
            }
        }
    }

    private func dependentCard(_ lead: Lead) -> some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 0) {
                Text(lead.therapyFor == .infantil ? "SOBRE A CRIANÇA" : "SOBRE QUEM VAI SER ATENDIDO")
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 12)

                if lead.therapyFor == .infantil {
                    infoRow("Nome", lead.childName ?? "—")
                    Divider().overlay(Theme.border).padding(.vertical, 10)
                    infoRow("Idade", lead.childAge.map { "\($0) anos" } ?? "—")
                } else {
                    infoRow("Nome", lead.relativeName ?? "—")
                    Divider().overlay(Theme.border).padding(.vertical, 10)
                    infoRow("Contato", lead.relativeContact.map(PatientMask.whatsapp) ?? "—")
                }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String, destaque: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
            Text(value.isEmpty ? "—" : value)
                .font(Theme.body(destaque ? 15 : 14, weight: destaque ? .medium : .regular))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Lead {
    var primeiroNome: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}
