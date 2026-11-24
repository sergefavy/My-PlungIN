import Foundation
import WatchConnectivity

/// Côté iPhone : envoie la page choisie à la montre et relaie ses demandes au pont du Mac.
/// La montre ne parle pas au Mac directement : elle passe par l'iPhone.
final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()

    /// Branché par l'appli au démarrage : charge un plugin via le pont.
    @MainActor var load: ((String, @escaping (Bool, String) -> Void) -> Void)?

    private var lastPushed: Data?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    @MainActor func push(_ page: Page?) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let pads = (page?.pads ?? []).map { WatchPad(label: $0.label, searchName: $0.searchName, colorHex: $0.colorHex) }
        let data = (try? JSONEncoder().encode(WatchPage(name: page?.name ?? "Desk", pads: pads))) ?? Data()
        guard data != lastPushed else { return }
        lastPushed = data
        try? WCSession.default.updateApplicationContext(["page": data])
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let name = message["load"] as? String else {
            replyHandler(["ok": false, "message": "Demande inconnue"])
            return
        }
        Task { @MainActor in
            guard let load = self.load else {
                replyHandler(["ok": false, "message": "Ouvre Desk sur l'iPhone"])
                return
            }
            load(name) { ok, text in replyHandler(["ok": ok, "message": text]) }
        }
    }
}
