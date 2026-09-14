import Foundation
import Observation
import SwiftUI

// MARK: - Eventos em tempo real

enum SupRealtimeEvent {
    case ready
    case message(ticketId: String, message: SupMessage)
    case ticket(SupTicket)
    case typing(ticketId: String, role: SupSenderRole, name: String?)
    case read(ticketId: String, role: SupSenderRole, at: Date?)
    /// Conexão (re)aberta: telas abertas buscam o que perderam enquanto estava fora.
    case connected
}

enum SupConnectionState: Equatable {
    case idle, connecting, online, waiting
}

// MARK: - Cliente WebSocket

/// WebSocket nativo (`URLSessionWebSocketTask`) — o app segue sem dependência
/// de terceiros.
///
/// Autentica por ticket de uso único: cada conexão, inclusive cada
/// reconexão, pede um ticket novo. Um ticket vencido nunca é reaproveitado.
@MainActor
final class SupRealtimeClient: NSObject {
    var onEvent: @MainActor (SupRealtimeEvent) -> Void = { _ in }
    var onState: @MainActor (SupConnectionState) -> Void = { _ in }

    private(set) var state: SupConnectionState = .idle

    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    private var socket: URLSessionWebSocketTask?
    private var wanted = false
    private var generation = 0
    private var attempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    /// 1 s, 2 s, 5 s, 10 s e depois de 30 em 30 s.
    private static let backoff: [UInt64] = [1, 2, 5, 10, 30]

    func start() {
        wanted = true
        guard socket == nil, reconnectTask == nil, state != .connecting else { return }
        connect()
    }

    func stop() {
        wanted = false
        generation += 1
        teardown()
        setState(.idle)
    }

    /// Voltou a rede: não espera o backoff terminar.
    func reconnectNow() {
        guard wanted else { return }
        generation += 1
        teardown()
        attempt = 0
        connect()
    }

    func send(event: String, data: [String: Any]) {
        guard let socket, state == .online,
              let payload = try? JSONSerialization.data(withJSONObject: ["event": event, "data": data]),
              let text = String(data: payload, encoding: .utf8)
        else { return }
        socket.send(.string(text)) { _ in }
    }

    // MARK: Conexão

    private func setState(_ novo: SupConnectionState) {
        guard state != novo else { return }
        state = novo
        onState(novo)
    }

    private func teardown() {
        reconnectTask?.cancel()
        reconnectTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func connect() {
        generation += 1
        let gen = generation
        setState(.connecting)
        Task { [weak self] in
            guard let self else { return }
            do {
                let grant = try await SupportAPI.realtimeTicket()
                guard gen == self.generation, self.wanted else { return }
                guard var components = URLComponents(string: grant.url) else { throw URLError(.badURL) }
                var items = components.queryItems ?? []
                items.append(URLQueryItem(name: "ticket", value: grant.ticket))
                components.queryItems = items
                guard let url = components.url else { throw URLError(.badURL) }
                let task = self.session.webSocketTask(with: url)
                self.socket = task
                task.resume()
                self.receive(on: task, generation: gen)
            } catch is CancellationError {
                guard gen == self.generation else { return }
                self.scheduleReconnect()
            } catch let error as APIError where error.isUnauthorized {
                // Sessão caiu: o APIClient já leva ao login. Não insiste.
                self.wanted = false
                self.setState(.idle)
            } catch {
                guard gen == self.generation else { return }
                self.scheduleReconnect()
            }
        }
    }

    private func receive(on task: URLSessionWebSocketTask, generation gen: Int) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, gen == self.generation, task === self.socket else { return }
                switch result {
                case let .success(message):
                    switch message {
                    case let .string(text): self.handle(Data(text.utf8))
                    case let .data(data): self.handle(data)
                    @unknown default: break
                    }
                    self.receive(on: task, generation: gen)
                case .failure:
                    self.lost(task)
                }
            }
        }
    }

    fileprivate func didOpen(_ task: URLSessionTask) {
        guard task === socket else { return }
        attempt = 0
        setState(.online)
        if let socket { startHeartbeat(socket) }
        onEvent(.connected)
    }

    fileprivate func lost(_ task: URLSessionTask) {
        guard task === socket else { return }
        socket = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        if wanted {
            scheduleReconnect()
        } else {
            setState(.idle)
        }
    }

    private func scheduleReconnect() {
        guard wanted, reconnectTask == nil else { return }
        setState(.waiting)
        let delay = Self.backoff[min(attempt, Self.backoff.count - 1)]
        attempt += 1
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.reconnectTask = nil
            guard self.wanted else { return }
            self.connect()
        }
    }

    private func startHeartbeat(_ task: URLSessionWebSocketTask) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25 * 1_000_000_000)
                guard let self, !Task.isCancelled, task === self.socket else { return }
                self.send(event: "ping", data: [:])
                task.sendPing { error in
                    guard error != nil else { return }
                    Task { @MainActor [weak self] in
                        guard let self, task === self.socket else { return }
                        task.cancel(with: .abnormalClosure, reason: nil)
                        self.lost(task)
                    }
                }
            }
        }
    }

    // MARK: Eventos

    private func handle(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String
        else { return }
        let payload: Data = {
            guard let raw = object["data"], JSONSerialization.isValidJSONObject(raw),
                  let encoded = try? JSONSerialization.data(withJSONObject: raw)
            else { return Data("{}".utf8) }
            return encoded
        }()
        let decoder = SupJSON.decoder

        switch event {
        case "support.ready":
            onEvent(.ready)
        case "support.message":
            struct Payload: Decodable { let ticketId: String; let message: SupMessage }
            if let value = try? decoder.decode(Payload.self, from: payload) {
                onEvent(.message(ticketId: value.ticketId, message: value.message))
            }
        case "support.ticket":
            struct Payload: Decodable { let ticket: SupTicket }
            if let value = try? decoder.decode(Payload.self, from: payload) {
                onEvent(.ticket(value.ticket))
            }
        case "support.typing":
            struct Payload: Decodable { let ticketId: String; let role: SupSenderRole; let name: String? }
            if let value = try? decoder.decode(Payload.self, from: payload) {
                onEvent(.typing(ticketId: value.ticketId, role: value.role, name: value.name))
            }
        case "support.read":
            struct Payload: Decodable { let ticketId: String; let role: SupSenderRole; let at: Date? }
            if let value = try? decoder.decode(Payload.self, from: payload) {
                onEvent(.read(ticketId: value.ticketId, role: value.role, at: value.at))
            }
        default:
            // `pong` e eventos que esta versão do app não conhece.
            break
        }
    }
}

extension SupRealtimeClient: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor in self.didOpen(webSocketTask) }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        // 4401 = ticket inválido/vencido: a reconexão já pede outro.
        Task { @MainActor in self.lost(webSocketTask) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in self.lost(task) }
    }
}

// MARK: - Estado compartilhado do suporte

/// Resumo (não lidas, atendimento aberto), lista de atendimentos e o socket.
/// Uma instância só: o badge do menu e a conversa aberta leem o mesmo estado.
@MainActor
@Observable
final class SupportStore {
    static let shared = SupportStore()

    private(set) var summary: SupSummary?
    private(set) var tickets: [SupTicket] = []
    private(set) var hasLoadedTickets = false
    private(set) var isLoadingTickets = false
    var ticketsError: String?
    private(set) var connection: SupConnectionState = .idle

    var unreadCount: Int { summary?.unreadCount ?? 0 }
    var openTicketId: String? { summary?.openTicketId ?? openTicket?.id }
    var openTicket: SupTicket? { tickets.first { !$0.status.isResolved } }
    var resolvedTickets: [SupTicket] { tickets.filter(\.status.isResolved) }

    @ObservationIgnored private let client = SupRealtimeClient()
    @ObservationIgnored private var listeners: [UUID: @MainActor (SupRealtimeEvent) -> Void] = [:]
    @ObservationIgnored private var summaryTask: Task<Void, Never>?
    @ObservationIgnored private var running = false

    private init() {
        client.onEvent = { [weak self] event in self?.handle(event) }
        client.onState = { [weak self] state in self?.connection = state }
    }

    // MARK: Ciclo de vida (casca autenticada)

    func start() {
        guard !running else { return }
        running = true
        client.start()
        Task { await refreshSummary() }
    }

    /// Logout: o próximo terapeuta neste aparelho não vê nada do anterior.
    func stop() {
        running = false
        client.stop()
        summaryTask?.cancel()
        summary = nil
        tickets = []
        hasLoadedTickets = false
        ticketsError = nil
    }

    /// O iOS derruba o socket em segundo plano; na volta, conecta de novo.
    func appBecameActive() {
        guard running else { return }
        client.start()
        Task { await refreshSummary() }
    }

    func appWentToBackground() {
        guard running else { return }
        client.stop()
    }

    func networkChanged(isOnline: Bool) {
        guard running, isOnline else { return }
        client.start()
        client.reconnectNow()
        Task { await refreshSummary() }
    }

    // MARK: Dados

    func refreshSummary() async {
        guard running else { return }
        if let value = try? await SupportAPI.summary() {
            summary = value
        }
    }

    func loadTickets() async {
        isLoadingTickets = true
        ticketsError = nil
        defer { isLoadingTickets = false }
        do {
            let page = try await SupportAPI.tickets()
            tickets = page.items.sorted(by: Self.ordem)
            hasLoadedTickets = true
        } catch is CancellationError {
            return
        } catch {
            ticketsError = (error as? APIError)?.message
                ?? "Não foi possível carregar seus atendimentos. Confira a conexão e tente de novo."
        }
        await refreshSummary()
    }

    func didCreate(_ ticket: SupTicket) {
        upsert(ticket)
        summary = SupSummary(openTicketId: ticket.id, unreadCount: summary?.unreadCount ?? 0)
    }

    func upsert(_ ticket: SupTicket) {
        if let index = tickets.firstIndex(where: { $0.id == ticket.id }) {
            tickets[index] = ticket
        } else {
            tickets.append(ticket)
        }
        tickets.sort(by: Self.ordem)
    }

    /// Aberto primeiro; depois o que teve movimento mais recente.
    private static func ordem(_ a: SupTicket, _ b: SupTicket) -> Bool {
        if a.status.isResolved != b.status.isResolved { return !a.status.isResolved }
        return a.lastActivity > b.lastActivity
    }

    // MARK: Tempo real

    func sendTyping(ticketId: String) {
        client.send(event: "support.typing", data: ["ticketId": ticketId])
    }

    func observe(_ handler: @escaping @MainActor (SupRealtimeEvent) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = handler
        return id
    }

    func removeObserver(_ id: UUID) {
        listeners[id] = nil
    }

    private func handle(_ event: SupRealtimeEvent) {
        switch event {
        case let .ticket(ticket):
            if hasLoadedTickets { upsert(ticket) }
            scheduleSummaryRefresh()
        case .message, .connected:
            scheduleSummaryRefresh()
        default:
            break
        }
        for handler in listeners.values { handler(event) }
    }

    /// Várias mudanças juntas (mensagem + ticket + leitura) viram um pedido só.
    private func scheduleSummaryRefresh() {
        summaryTask?.cancel()
        summaryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshSummary()
        }
    }
}
