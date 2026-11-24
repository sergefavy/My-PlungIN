import AppKit
import Foundation

/// Lit (sans jamais écrire) ce que Plugindex garde dans ~/.plugindex
/// pour montrer tes vrais plugins et leur image sur la télécommande.
enum Library {
    static let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".plugindex")

    static func plugins() -> [PluginInfo] {
        let categories = readJSON("plugin-categories.json") as? [String: String] ?? [:]
        var result: [PluginInfo] = []

        // Plugins tiers vus par Plugindex : clés « editeur~nom ».
        if let seen = readJSON("seen-plugins.json") as? [String: Any], let keys = seen["keys"] as? [String] {
            for key in keys {
                let parts = key.split(separator: "~", maxSplits: 1).map(String.init)
                let maker = parts.count == 2 ? pretty(parts[0]) : ""
                let name = pretty(parts.last ?? key)
                let compact = (parts.last ?? key).filter { $0.isLetter || $0.isNumber }
                let category = categories[compact] ?? categories[(parts.first ?? "") + compact] ?? ""
                let kind = category.hasPrefix("Instrument") ? "Instrument" : "Effet"
                result.append(PluginInfo(key: key, name: name, maker: maker, kind: kind, hasImage: imageURL(for: key) != nil))
            }
        }

        // Plugins de Logic (Apple) connus de Plugindex.
        if let logic = readJSON("logic-catalog.json") as? [String: Any] {
            for (field, kind) in [("instruments", "Instrument"), ("effects", "Effet")] {
                for entry in logic[field] as? [[String: Any]] ?? [] {
                    guard let name = entry["name"] as? String else { continue }
                    let key = "apple~" + name.lowercased().replacingOccurrences(of: " ", with: "-")
                    if result.contains(where: { $0.key == key }) { continue }
                    result.append(PluginInfo(key: key, name: name, maker: "Apple", kind: kind, hasImage: false))
                }
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Image du plugin, réduite en JPEG pour passer vite sur le Wi-Fi.
    static func imageData(for key: String, maxSide: CGFloat = 360) -> Data? {
        guard let url = imageURL(for: key), let image = NSImage(contentsOf: url) else { return nil }
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: target))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }

    /// Réglage `openHotkey` de Plugindex (ex. « Control+Alt+D »).
    static func openHotkey() -> String {
        (readJSON("settings.json") as? [String: Any])?["openHotkey"] as? String ?? "Control+Alt+D"
    }

    // MARK: - Détails

    private static func imageURL(for key: String) -> URL? {
        let png = folder.appendingPathComponent("images/\(key).png")
        if FileManager.default.fileExists(atPath: png.path) { return png }
        let thumbs = folder.appendingPathComponent("thumbs")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: thumbs.path)) ?? []
        return files.first { $0.hasPrefix(key + "-") || $0.hasPrefix(key + ".") }.map { thumbs.appendingPathComponent($0) }
    }

    private static func readJSON(_ name: String) -> Any? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// « addictive-drums-2 » → « Addictive Drums 2 », « triton » → « TRITON » reste lisible.
    private static func pretty(_ slug: String) -> String {
        slug.split(separator: "-").map { word in
            word.count <= 2 ? word.uppercased() : word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}
