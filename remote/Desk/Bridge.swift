import Foundation
import Network
import Observation
import UIKit

/// Lien avec le pont du Mac : découverte Bonjour, appairage, commandes.
@MainActor
@Observable
final class Bridge {
    enum State: Equatable { case searching, connecting, needsCode, ready, failed(String) }

    private(set) var state: State = .searching
    private(set) var macs: [NWBrowser.Result] = []
    private(set) var library: [PluginInfo] = []
    private(set) var images: [String: UIImage] = [:]
    private(set) var toast: (text: String, ok: Bool)?
    private(set) var macName: String?

    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var connection: NWConnection?
    @ObservationIgnored private var requestedImages = Set<String>()
    @ObservationIgnored private var pendingLoads: [String: [(Bool, String) -> Void]] = [:]

    private var token: String? {
        get { UserDefaults.standard.string(forKey: "bridgeToken") }
        set { UserDefaults.standard.set(newValue, forKey: "bridgeToken") }
    }
    private var savedMac: String? {
        get { UserDefaults.standard.string(forKey: "bridgeMac") }
        set { UserDefaults.standard.set(newValue, forKey: "bridgeMac") }
    }

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: Bridge.parameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.found(Array(results)) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func connect(to result: NWBrowser.Result) {
        connection?.cancel()
        if case let .service(name, _, _, _) = result.endpoint {
            if name != savedMac { token = nil }
            savedMac = name
            macName = name
        }
        state = .connecting
        let connection = NWConnection(to: result.endpoint, using: Bridge.parameters())
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.connectionChanged(state) }
        }
        connection.start(queue: .main)
        self.connection = connection
        receive()
    }

    func pair(code: String) {
        send(Msg("pair", code: code, device: UIDevice.current.name))
    }

    func unpair() {
        token = nil
        savedMac = nil
        connection?.cancel()
        connection = nil
        library = []
        state = .searching
    }

    func refreshLibrary() { send(Msg("library")) }

    func image(for key: String) -> UIImage? {
        if let image = images[key] { return image }
        if !requestedImages.contains(key), library.first(where: { $0.key == key })?.hasImage == true {
            requestedImages.insert(key)
            send(Msg("image", key: key))
        }
        return nil
    }

    /// Demande au pont de charger un plugin dans Plugindex.
    func load(_ name: String, done: ((Bool, String) -> Void)? = nil) {
        guard state == .ready else {
            done?(false, "Pas connecté au Mac")
            return
        }
        if let done { pendingLoads[name, default: []].append(done) }
        send(Msg("load", name: name))
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - Détails

    private static func parameters() -> NWParameters {
        let params = NWParameters.tcp
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        ws.maximumMessageSize = 4 * 1024 * 1024
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        params.includePeerToPeer = true
        return params
    }

    private func found(_ results: [NWBrowser.Result]) {
        macs = results
        // Se reconnecter tout seul au Mac déjà appairé.
        guard connection == nil, let savedMac else { return }
        if let match = results.first(where: {
            if case let .service(name, _, _, _) = $0.endpoint { return name == savedMac }
            return false
        }) {
            connect(to: match)
        }
    }

    private func connectionChanged(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            if let token { send(Msg("hello", token: token)) } else { state = .needsCode }
        case let .failed(error):
            state = .failed(error.localizedDescription)
            connection = nil
        case .cancelled:
            connection = nil
            if state == .ready { state = .searching }
        default:
            break
        }
    }

    private func receive() {
        connection?.receiveMessage { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, let msg = Msg.decode(data) { self.handle(msg) }
                if error == nil { self.receive() }
            }
        }
    }

    private func handle(_ msg: Msg) {
        switch msg.type {
        case "paired":
            token = msg.token
            state = .ready
            refreshLibrary()
        case "ready":
            state = .ready
            refreshLibrary()
            if msg.ok == false { show("Autorise l'Accessibilité pour le pont sur le Mac", ok: false) }
            if let message = msg.message { show(message, ok: false) }
        case "denied":
            token = nil
            state = .needsCode
            show(msg.message ?? "Refusé", ok: false)
        case "library":
            library = msg.plugins ?? []
        case "image":
            if let key = msg.key, let data = msg.data.flatMap({ Data(base64Encoded: $0) }), let image = UIImage(data: data) {
                images[key] = image
            }
        case "result":
            let ok = msg.ok ?? false
            let text = msg.message ?? ""
            show(text, ok: ok)
            if let name = msg.name, let waiting = pendingLoads.removeValue(forKey: name) {
                waiting.forEach { $0(ok, text) }
            }
            UINotificationFeedbackGenerator().notificationOccurred(ok ? .success : .error)
        default:
            break
        }
    }

    private func show(_ text: String, ok: Bool) {
        toast = (text, ok)
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toast?.text == text { toast = nil }
        }
    }

    private func send(_ msg: Msg) {
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "msg", metadata: [meta])
        connection?.send(content: msg.encoded(), contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }
}
