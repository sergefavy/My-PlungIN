import SwiftUI
import WatchConnectivity
import WatchKit

@main
struct DeskWatchApp: App {
    @State private var link = PhoneLink()

    var body: some Scene {
        WindowGroup {
            WatchDesk().environment(link).task { link.activate() }
        }
    }
}

/// Côté montre : reçoit la page choisie sur l'iPhone et lui demande de charger un plugin.
@MainActor
@Observable
final class PhoneLink: NSObject, WCSessionDelegate {
    private(set) var page = WatchPage(name: "Desk", pads: [])
    private(set) var status: (text: String, ok: Bool)?
    private(set) var busy: String?

    func activate() {
        if let data = UserDefaults.standard.data(forKey: "page"), let saved = try? JSONDecoder().decode(WatchPage.self, from: data) {
            page = saved
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func load(_ pad: WatchPad) {
        guard WCSession.default.isReachable else {
            show("Ouvre Desk sur l'iPhone", ok: false)
            return
        }
        busy = pad.id
        WCSession.default.sendMessage(["load": pad.searchName], replyHandler: { reply in
            let ok = reply["ok"] as? Bool ?? false
            let text = reply["message"] as? String ?? ""
            Task { @MainActor in
                self.busy = nil
                self.show(ok ? "Chargé" : text, ok: ok)
            }
        }, errorHandler: { error in
            Task { @MainActor in
                self.busy = nil
                self.show(error.localizedDescription, ok: false)
            }
        })
    }

    private func show(_ text: String, ok: Bool) {
        status = (text, ok)
        WKInterfaceDevice.current().play(ok ? .success : .failure)
        Task {
            try? await Task.sleep(for: .seconds(2))
            if status?.text == text { status = nil }
        }
    }

    private func apply(_ context: [String: Any]) {
        guard let data = context["page"] as? Data, let page = try? JSONDecoder().decode(WatchPage.self, from: data) else { return }
        self.page = page
        UserDefaults.standard.set(data, forKey: "page")
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in self.apply(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }
}

struct WatchDesk: View {
    @Environment(PhoneLink.self) private var link

    var body: some View {
        NavigationStack {
            ScrollView {
                if link.page.pads.isEmpty {
                    Text("Choisis la page de la montre dans Desk sur l'iPhone.")
                        .font(.footnote).multilineTextAlignment(.center).padding()
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(link.page.pads) { pad in
                        Button { link.load(pad) } label: {
                            ZStack {
                                Text(pad.label).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                                    .minimumScaleFactor(0.6).multilineTextAlignment(.center)
                                    .opacity(link.busy == pad.id ? 0.3 : 1)
                                if link.busy == pad.id { ProgressView() }
                            }
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .background(Color(hex: pad.colorHex).gradient, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                if let status = link.status {
                    Label(status.text, systemImage: status.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(status.ok ? .green : .orange).padding(.top, 6)
                }
            }
            .navigationTitle(link.page.name)
            .containerBackground(Theme.wall.gradient, for: .navigation)
        }
    }
}
