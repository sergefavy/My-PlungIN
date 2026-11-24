import Foundation

/// Nom du service Bonjour annoncé par le pont sur le Wi-Fi.
public let serviceType = "_plugremote._tcp"

/// Un plugin tel que la télécommande l'affiche.
public struct PluginInfo: Codable, Hashable, Identifiable, Sendable {
    /// Clé « éditeur~nom » (même forme que les fichiers de Plugindex).
    public var key: String
    /// Nom tapé dans la recherche de Plugindex pour le charger.
    public var name: String
    public var maker: String
    /// « Instrument » ou « Effet ».
    public var kind: String
    public var hasImage: Bool
    public var id: String { key }

    public init(key: String, name: String, maker: String, kind: String, hasImage: Bool) {
        self.key = key; self.name = name; self.maker = maker; self.kind = kind; self.hasImage = hasImage
    }
}

/// Message échangé entre la télécommande et le pont (JSON, une trame WebSocket texte).
///
/// Télécommande → pont : `pair` (code, device), `hello` (token), `library`, `image` (key), `load` (name).
/// Pont → télécommande : `paired` (token), `denied` (message), `ready`, `library` (plugins),
/// `image` (key, data base64), `result` (name, ok, message).
public struct Msg: Codable, Sendable {
    public var type: String
    public var token: String?
    public var code: String?
    public var device: String?
    public var name: String?
    public var key: String?
    public var data: String?
    public var ok: Bool?
    public var message: String?
    public var plugins: [PluginInfo]?

    public init(_ type: String, token: String? = nil, code: String? = nil, device: String? = nil,
                name: String? = nil, key: String? = nil, data: String? = nil, ok: Bool? = nil,
                message: String? = nil, plugins: [PluginInfo]? = nil) {
        self.type = type; self.token = token; self.code = code; self.device = device
        self.name = name; self.key = key; self.data = data; self.ok = ok
        self.message = message; self.plugins = plugins
    }

    public func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
    public static func decode(_ data: Data) -> Msg? { try? JSONDecoder().decode(Msg.self, from: data) }
}

/// Bouton tel que la montre le reçoit de l'iPhone.
public struct WatchPad: Codable, Hashable, Identifiable, Sendable {
    public var label: String
    public var searchName: String
    public var colorHex: String
    public var id: String { label + searchName }
    public init(label: String, searchName: String, colorHex: String) {
        self.label = label; self.searchName = searchName; self.colorHex = colorHex
    }
}

public struct WatchPage: Codable, Sendable {
    public var name: String
    public var pads: [WatchPad]
    public init(name: String, pads: [WatchPad]) { self.name = name; self.pads = pads }
}
