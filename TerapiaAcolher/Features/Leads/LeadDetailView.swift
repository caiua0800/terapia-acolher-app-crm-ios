import SwiftUI
import UIKit

/// Ficha do lead: quem é, em que pé está, e o próximo passo à mão — mesma
/// tela do web (`web-app/components/leads/conteudo-do-lead.tsx`). O lead vem
/// do sistema de leads via CRM; o status e a conversão são gravados no CRM.
struct LeadDetailView: View {
    let leadId: String

    @State private var store = LeadsStore.shared
    @State private var showConvert = false
    @State private var showConverted = false
    @State private var salvando: LeadStatus?
    @State private var modeloId: String?
    /// Edição à mão vence o modelo até o próximo toque num modelo.
    @State private var editado: String?
    @State private var copiado = false
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
            VStack(alignment: .leading, spacing: 20) {
                header(lead)
                if lead.sla == .late { avisoAtrasado }
                secao("Em que pé está") { etapas(lead) }
                secao("Mensagem") { mensagem(lead) }
                paciente(lead)
                secao("O que contou") { oQueContou(lead) }
                if lead.therapyFor == .infantil {
                    secao("Sobre a criança") {
                        grade([
                            ("Nome", lead.childName ?? "", nil),
                            ("Idade", lead.childAge.map { "\($0) anos" } ?? "", nil),
                        ])
                    }
                } else if lead.therapyFor == .outraPessoa {
                    secao("Sobre quem vai ser atendido") {
                        grade([
                            ("Nome", lead.relativeName ?? "", nil),
                            ("Contato", lead.relativeContact.map(PatientMask.whatsapp) ?? "", lead.relativeContact),
                        ])
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
    }

    // MARK: Cabeçalho

    private func header(_ lead: Lead) -> some View {
        HStack(alignment: .top, spacing: 14) {
            InitialAvatar(name: lead.name, colorHex: nil, size: 58)
            VStack(alignment: .leading, spacing: 6) {
                Text(lead.name)
                    .font(Theme.serifTitle(23))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    let (cor, fundo) = LeadStyle.colors(for: lead.status)
                    StatusBadge(label: lead.status.shortLabel, color: cor, background: fundo)
                    Text("chegou \(lead.elapsedLabel)")
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(Self.dataHora.string(from: lead.receivedAt))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private static let dataHora: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "dd/MM/yyyy 'às' HH:mm"
        return f
    }()

    private var avisoAtrasado: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark.fill")
                .foregroundStyle(Theme.danger)
            (Text("Esperando há mais de um dia. ").fontWeight(.semibold)
                + Text("Quanto antes o primeiro contato, maior a chance de virar paciente."))
                .font(Theme.body(13))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    // MARK: Etapas

    private func etapas(_ lead: Lead) -> some View {
        let caminho: [LeadStatus] = [.novo, .tentandoContato, .negociando, .agendado]
        let indiceAtual = caminho.firstIndex(of: lead.status)
        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Array(caminho.enumerated()), id: \.element) { i, etapa in
                    let feito = indiceAtual.map { i <= $0 } ?? false
                    let atual = lead.status == etapa
                    Button {
                        escolher(etapa, lead)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Capsule()
                                .fill(feito ? lead.status.tint : Theme.border)
                                .frame(height: 4)
                            HStack(spacing: 3) {
                                if salvando == etapa {
                                    ProgressView().controlSize(.mini).tint(Theme.textPrimary)
                                } else if atual {
                                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                }
                                Text(etapa.label)
                                    .font(Theme.body(11.5, weight: .semibold))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                                    .multilineTextAlignment(.leading)
                            }
                            .foregroundStyle(Theme.textPrimary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(atual ? etapa.tint : Theme.border, lineWidth: atual ? 2 : 1)
                        )
                    }
                    .buttonStyle(.pressable)
                    .disabled(salvando != nil)
                }
            }
            Button {
                escolher(.naoConverteu, lead)
            } label: {
                HStack(spacing: 6) {
                    if salvando == .naoConverteu { ProgressView().controlSize(.mini) }
                    Text(lead.status == .naoConverteu ? "Marcado como não converteu" : "Não converteu")
                }
                .font(Theme.body(13, weight: .medium))
                .foregroundStyle(lead.status == .naoConverteu ? Theme.textPrimary : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(lead.status == .naoConverteu ? Color(hex: 0xF1EDE4) : .clear, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.pressableSubtle)
            .disabled(salvando != nil)
        }
    }

    private func escolher(_ etapa: LeadStatus, _ lead: Lead) {
        guard etapa != lead.status, salvando == nil else { return }
        salvando = etapa
        Task {
            await store.updateStatus(lead.id, to: etapa)
            salvando = nil
            if store.lead(id: lead.id)?.status == etapa { Haptics.success() }
        }
    }

    // MARK: Mensagem no WhatsApp

    @ViewBuilder
    private func mensagem(_ lead: Lead) -> some View {
        if lead.whatsapp.isEmpty {
            Text("Este lead chegou sem número de WhatsApp.")
                .font(Theme.body(13.5))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
        } else {
            let modelos = lead.messageTemplates(therapistName: SessionStore.shared.user?.name ?? "")
            let escolhido = modeloId ?? Lead.suggestedTemplateId(for: lead.status)
            let texto = editado ?? modelos.first { $0.id == escolhido }?.text ?? ""
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(modelos) { m in
                            Button {
                                Haptics.tap()
                                modeloId = m.id
                                editado = nil
                            } label: {
                                Text(m.title)
                                    .font(Theme.body(12.5, weight: escolhido == m.id ? .semibold : .regular))
                                    .foregroundStyle(escolhido == m.id ? Theme.primary : Theme.textSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(escolhido == m.id ? Theme.primarySoft : .clear, in: Capsule())
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }
                TextEditor(text: Binding(get: { texto }, set: { editado = $0 }))
                    .font(Theme.body(14.5))
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                HStack(spacing: 8) {
                    Button {
                        abrirWhatsApp(lead, texto: texto)
                    } label: {
                        Label("Abrir no WhatsApp", systemImage: "paperplane.fill")
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color(hex: 0x25D366), in: Capsule())
                    }
                    .buttonStyle(.pressable)
                    .disabled(texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        UIPasteboard.general.string = texto
                        Haptics.success()
                        copiado = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.6))
                            copiado = false
                        }
                    } label: {
                        Image(systemName: copiado ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(copiado ? Theme.success : Theme.textSecondary)
                            .frame(width: 46, height: 46)
                            .background(Theme.surface, in: Circle())
                            .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Copiar mensagem")
                }
                if lead.status == .novo {
                    (Text("Ao abrir a conversa, o lead passa para ") + Text("Tentando contato").fontWeight(.semibold) + Text("."))
                        .font(Theme.body(11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.border, lineWidth: 1))
        }
    }

    private func abrirWhatsApp(_ lead: Lead, texto: String) {
        let digits = lead.whatsapp.filter(\.isNumber)
        let encoded = texto.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://wa.me/\(digits)?text=\(encoded)") else { return }
        openURL(url)
        // Quem abre a conversa com um lead novo começou o contato: o quadro
        // acompanha sem o terapeuta precisar lembrar de mudar a etapa.
        if lead.status == .novo {
            Task { await store.updateStatus(lead.id, to: .tentandoContato) }
        }
    }

    // MARK: Paciente

    @ViewBuilder
    private func paciente(_ lead: Lead) -> some View {
        if lead.convertedPatientId != nil {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.success, in: Circle())
                Text("Já é seu paciente.")
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .padding(14)
            .background(Theme.successSoft, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        } else {
            let destaque = lead.status == .agendado
            HStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 36, height: 36)
                    .background(Theme.primarySoft, in: Circle())
                Text(destaque
                     ? "Agendou? Crie a ficha — nome e WhatsApp já vão preenchidos."
                     : "Virou paciente? Crie a ficha sem redigitar.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Button {
                    Haptics.tap()
                    showConvert = true
                } label: {
                    Text("Criar paciente")
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(destaque ? .white : Theme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(destaque ? Theme.primary : Theme.primarySoft, in: Capsule())
                }
                .buttonStyle(.pressable)
            }
            .padding(14)
            .background(destaque ? Theme.primarySoft : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(destaque ? .clear : Theme.border, lineWidth: 1))
        }
    }

    // MARK: O que contou

    private func oQueContou(_ lead: Lead) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if lead.reason.isEmpty {
                Text("Não escreveu o motivo.")
                    .font(Theme.body(13.5))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text(lead.reason)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
            }
            grade([
                ("Terapia para", lead.therapyFor.label, nil),
                ("Melhor horário", lead.shift.label, nil),
                ("Quando chamar", lead.contactWhen, nil),
                ("Se identifica como", lead.gender.label, nil),
                ("Prefere terapeuta", lead.preferredTherapistGender == "feminino" ? "Mulher" : lead.preferredTherapistGender == "masculino" ? "Homem" : "Tanto faz", nil),
                ("WhatsApp", lead.whatsapp.isEmpty ? "" : lead.whatsappLegivel, lead.whatsapp.isEmpty ? nil : lead.whatsapp),
            ])
        }
    }

    /// Grade de dois em dois; o terceiro campo, quando existe, é o que o botão copia.
    private func grade(_ itens: [(String, String, String?)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(Array(itens.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.0)
                        .font(Theme.body(11.5))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 5) {
                        Text(item.1.isEmpty ? "—" : item.1)
                            .font(Theme.body(13.5, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                        if let copiar = item.2, !item.1.isEmpty {
                            Button {
                                UIPasteboard.general.string = copiar
                                Haptics.success()
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .accessibilityLabel("Copiar \(item.0)")
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                .padding(10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
            }
        }
    }

    private func secao<C: View>(_ titulo: String, @ViewBuilder _ conteudo: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titulo.uppercased())
                .font(Theme.body(11, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.textSecondary)
            conteudo()
        }
    }
}
