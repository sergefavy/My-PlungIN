import Network
import SwiftUI

@main
struct DeskApp: App {
    @State private var bridge = Bridge()
    @State private var layout = Layout()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(bridge)
                .environment(layout)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
                .task {
                    WatchLink.shared.load = { [bridge] name, done in bridge.load(name, done: done) }
                    WatchLink.shared.activate()
                    bridge.start()
                    try? await Task.sleep(for: .seconds(1))
                    WatchLink.shared.push(layout.watchPage)
                }
        }
    }
}

struct RootView: View {
    @Environment(Bridge.self) private var bridge

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background
            switch bridge.state {
            case .ready: DeskView()
            case .needsCode: PairView()
            default: FindMacView()
            }
            if let toast = bridge.toast {
                Label(toast.text, systemImage: toast.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: bridge.toast?.text)
        .foregroundStyle(Theme.cream)
    }
}

/// Liste des Mac où tourne le pont.
struct FindMacView: View {
    @Environment(Bridge.self) private var bridge

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "pianokeys").font(.system(size: 48)).foregroundStyle(Theme.gold)
            Text("Desk").font(.largeTitle.bold())
            if case let .failed(reason) = bridge.state {
                Text(reason).font(.footnote).foregroundStyle(.orange)
            }
            if bridge.state == .connecting {
                ProgressView("Connexion…")
            } else if bridge.macs.isEmpty {
                ProgressView()
                Text("Je cherche le pont sur ton Wi-Fi.\nOuvre « Pont Télécommande » sur le Mac.")
                    .multilineTextAlignment(.center).font(.callout).opacity(0.8)
            } else {
                ForEach(Array(bridge.macs.enumerated()), id: \.offset) { _, result in
                    Button { bridge.connect(to: result) } label: {
                        Label(Self.name(of: result), systemImage: "desktopcomputer")
                            .frame(maxWidth: 320).padding()
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
        .padding()
    }

    static func name(of result: NWBrowser.Result) -> String {
        if case let .service(name, _, _, _) = result.endpoint { return name }
        return "Mac"
    }
}

/// Saisie du code à 6 chiffres affiché dans la barre des menus du Mac.
struct PairView: View {
    @Environment(Bridge.self) private var bridge
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 18) {
            Text("Appairer avec \(bridge.macName ?? "le Mac")").font(.title2.bold())
            Text("Tape le code affiché par l'icône du pont dans la barre des menus du Mac.")
                .multilineTextAlignment(.center).font(.callout).opacity(0.8)
            TextField("000000", text: $code)
                .keyboardType(.numberPad)
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
                .padding(.vertical, 8)
                .background(Theme.wallDark, in: RoundedRectangle(cornerRadius: 12))
                .focused($focused)
                .onChange(of: code) {
                    code = String(code.filter(\.isNumber).prefix(6))
                    if code.count == 6 { bridge.pair(code: code) }
                }
            Button("Changer de Mac") { bridge.unpair() }.font(.footnote)
        }
        .padding()
        .onAppear { focused = true }
    }
}
