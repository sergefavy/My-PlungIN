import SwiftUI

@main
struct PontApp: App {
    @State private var server = Server()

    var body: some Scene {
        MenuBarExtra {
            PontMenu(server: server)
        } label: {
            Image(systemName: server.connected > 0 ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                .task { server.start() }
        }
        .menuBarExtraStyle(.window)
    }
}

struct PontMenu: View {
    let server: Server
    @State private var openDelay = Double(KeyDriver.openDelay)
    @State private var searchDelay = Double(KeyDriver.searchDelay)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pont Télécommande").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Code d'appairage").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(server.code).font(.system(size: 28, weight: .bold, design: .monospaced))
                    Spacer()
                    Button("Nouveau") { server.refreshCode() }
                }
                Text("Valable 5 minutes, une seule fois.").font(.caption2).foregroundStyle(.secondary)
            }

            Divider()
            status("Wi-Fi", server.listening ? "à l'écoute" : "arrêté", server.listening)
            status("Plugindex", KeyDriver.plugindexRunning ? "ouvert" : "fermé", KeyDriver.plugindexRunning)
            status("Accessibilité", KeyDriver.isTrusted ? "autorisée" : "à autoriser", KeyDriver.isTrusted)
            if !KeyDriver.isTrusted {
                Button("Autoriser l'Accessibilité…") { KeyDriver.askForAccess() }
            }
            Text("Appareils connectés : \(server.connected)").font(.caption)
            Text(server.lastAction).font(.caption).foregroundStyle(.secondary).lineLimit(2)

            if !server.devices.isEmpty {
                Divider()
                Text("Appareils appairés").font(.caption).foregroundStyle(.secondary)
                ForEach(server.devices.sorted(by: { $0.value < $1.value }), id: \.key) { token, name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button("Oublier") { server.forget(token) }.buttonStyle(.link)
                    }
                }
            }

            Divider()
            Text("Délais (si Plugindex rate des lettres)").font(.caption).foregroundStyle(.secondary)
            LabeledContent("Ouverture : \(Int(openDelay)) ms") {
                Slider(value: $openDelay, in: 150...1500, step: 50).onChange(of: openDelay) { KeyDriver.openDelay = Int(openDelay) }
            }
            LabeledContent("Recherche : \(Int(searchDelay)) ms") {
                Slider(value: $searchDelay, in: 150...2000, step: 50).onChange(of: searchDelay) { KeyDriver.searchDelay = Int(searchDelay) }
            }

            Divider()
            Button("Quitter le pont") { NSApplication.shared.terminate(nil) }
        }
        .padding()
        .frame(width: 300)
    }

    private func status(_ label: String, _ value: String, _ good: Bool) -> some View {
        HStack {
            Circle().fill(good ? .green : .orange).frame(width: 8, height: 8)
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}
