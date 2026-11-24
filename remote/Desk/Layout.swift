import Foundation
import Observation
import SwiftUI

/// Un bouton du desk : un plugin à charger, avec ton nom et ta couleur.
struct Pad: Codable, Identifiable, Hashable {
    var id = UUID()
    var pluginKey: String
    /// Ce qui est tapé dans Plugindex (modifiable si la recherche trouve mal).
    var searchName: String
    var label: String
    var colorHex: String
    var showImage = true
}

/// Une page du desk (ex. « Batterie », « Voix », « Mix »).
struct Page: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var columns: Int = 3
    var pads: [Pad] = []
}

/// Tout le desk personnalisé, enregistré sur l'appareil.
@MainActor
@Observable
final class Layout {
    var pages: [Page] { didSet { save() } }
    /// Page envoyée à la montre.
    var watchPageID: UUID? { didSet { save() } }

    static let palette = ["9B4A5C", "C98A96", "A0582A", "D6B36A", "6E8B74", "5F7896", "8A6B73", "3A1F27"]

    init() {
        if let data = UserDefaults.standard.data(forKey: "layout"),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            pages = saved.pages
            watchPageID = saved.watchPageID
        } else {
            pages = [Page(name: "Favoris")]
            watchPageID = nil
        }
    }

    var watchPage: Page? { pages.first { $0.id == watchPageID } ?? pages.first }

    func add(_ plugin: PluginInfo, to pageID: UUID) {
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else { return }
        let color = Layout.palette[pages[index].pads.count % Layout.palette.count]
        pages[index].pads.append(Pad(pluginKey: plugin.key, searchName: plugin.name, label: plugin.name, colorHex: color))
    }

    private struct Saved: Codable { var pages: [Page]; var watchPageID: UUID? }

    private func save() {
        if let data = try? JSONEncoder().encode(Saved(pages: pages, watchPageID: watchPageID)) {
            UserDefaults.standard.set(data, forKey: "layout")
        }
        WatchLink.shared.push(watchPage)
    }
}
