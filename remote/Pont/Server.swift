import Foundation
import Network
import Observation

/// Serveur WebSocket du pont, annoncé sur le Wi-Fi par Bonjour.
/// Un appareil doit d'abord s'appairer avec le code à 6 chiffres affiché dans la barre des menus.
@MainActor
@Observable
final class Server {
    private(set) var code = Server.newCode()
    private(set) var codeExpires = Date().addingTimeInterval(300)
    private(set) var devices: [String: String] = UserDefaults.standard.dictionary(forKey: "devices") as? [String: String] ?? [:]
    private(set) var connected = 0
    private(set) var lastAction = "En attente"
    private(set) var listening = false

    private var listener: NWListener?
    private var authorized = Set<ObjectIdentifier>()
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    func start() {
        let params = NWParameters.tcp
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        ws.maximumMessageSize = 4 * 1024 * 1024
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        params.includePeerToPeer = true
        do {
            let listener = try NWListener(using: params)
            listener.service = NWListener.Service(name: Host.current().localizedName ?? "Mac", type: serviceType)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.listening = (state == .ready) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            lastAction = "Impossible d'ouvrir le pont : \(error.localizedDescription)"
        }
    }

    func refreshCode() {
        code = Server.newCode()
        codeExpires = Date().addingTimeInterval(300)
    }

    func forget(_ token: String) {
        devices[token] = nil
        UserDefaults.standard.set(devices, forKey: "devices")
    }

    // MARK: - Connexions

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connected = connections.count
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                Task { @MainActor in self?.drop(id) }
            default: break
            }
        }
        connection.start(queue: .main)
        receive(on: connection)
    }

    private func drop(_ id: ObjectIdentifier) {
        connections[id] = nil
        authorized.remove(id)
        connected = connections.count
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, let msg = Msg.decode(data) { await self.handle(msg, from: connection) }
                if error == nil { self.receive(on: connection) } else { connection.cancel() }
            }
        }
    }

    private func handle(_ msg: Msg, from connection: NWConnection) async {
        let id = ObjectIdentifier(connection)
        switch msg.type {
        case "pair":
            guard Date() < codeExpires, msg.code == code else {
                send(Msg("denied", message: "Code faux ou expiré. Regarde le code dans la barre des menus du Mac."), to: connection)
                return
            }
            let token = UUID().uuidString
            devices[token] = msg.device ?? "Appareil"
            UserDefaults.standard.set(devices, forKey: "devices")
            authorized.insert(id)
            refreshCode()   // un code ne sert qu'une fois
            send(Msg("paired", token: token), to: connection)
            lastAction = "\(msg.device ?? "Appareil") appairé"

        case "hello":
            guard let token = msg.token, devices[token] != nil else {
                send(Msg("denied", message: "Cet appareil n'est plus appairé."), to: connection)
                return
            }
            authorized.insert(id)
            send(Msg("ready", ok: KeyDriver.isTrusted, message: KeyDriver.plugindexRunning ? nil : "Plugindex n'est pas ouvert"), to: connection)

        default:
            guard authorized.contains(id) else {
                send(Msg("denied", message: "Appaire d'abord cet appareil."), to: connection)
                return
            }
            await handleAuthorized(msg, from: connection)
        }
    }

    private func handleAuthorized(_ msg: Msg, from connection: NWConnection) async {
        switch msg.type {
        case "library":
            send(Msg("library", plugins: Library.plugins()), to: connection)
        case "image":
            guard let key = msg.key else { return }
            send(Msg("image", key: key, data: Library.imageData(for: key)?.base64EncodedString()), to: connection)
        case "load":
            guard let name = msg.name, !name.isEmpty else { return }
            let result = await KeyDriver.load(name)
            lastAction = result.message
            send(Msg("result", name: name, ok: result.ok, message: result.message), to: connection)
        default:
            break
        }
    }

    private func send(_ msg: Msg, to connection: NWConnection) {
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "msg", metadata: [meta])
        connection.send(content: msg.encoded(), contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }

    private static func newCode() -> String { String(format: "%06d", Int.random(in: 0...999_999)) }
}
