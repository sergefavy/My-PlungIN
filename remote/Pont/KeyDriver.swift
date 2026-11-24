import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Pilote Plugindex comme si tu étais au clavier : son raccourci d'ouverture,
/// le nom du plugin dans la recherche, puis Entrée. Rien d'autre.
@MainActor
enum KeyDriver {
    static let plugindexBundle = "com.dylanedmunds.plugindex"

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Affiche la demande d'autorisation Accessibilité de macOS.
    static func askForAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static var plugindexRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == plugindexBundle }
    }

    /// Délais réglables (en millisecondes) depuis le menu du pont.
    static var openDelay: Int {
        get { UserDefaults.standard.object(forKey: "openDelay") as? Int ?? 450 }
        set { UserDefaults.standard.set(newValue, forKey: "openDelay") }
    }
    static var searchDelay: Int {
        get { UserDefaults.standard.object(forKey: "searchDelay") as? Int ?? 600 }
        set { UserDefaults.standard.set(newValue, forKey: "searchDelay") }
    }

    static func load(_ name: String) async -> (ok: Bool, message: String) {
        guard isTrusted else {
            askForAccess()
            return (false, "Autorise « Pont Télécommande » dans Réglages Système > Confidentialité > Accessibilité.")
        }
        guard plugindexRunning else {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: plugindexBundle) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
            return (false, "Plugindex n'était pas ouvert : je viens de le lancer, réessaie dans quelques secondes.")
        }
        guard let hotkey = Hotkey(Library.openHotkey()) else {
            return (false, "Raccourci Plugindex illisible : \(Library.openHotkey())")
        }

        // Le raccourci ouvre ET ferme la fenêtre de Plugindex : on ne l'envoie que si elle n'est pas
        // déjà devant, et on ne tape jamais rien tant que Plugindex n'a pas le clavier
        // (sinon les lettres partiraient dans Logic, où ce sont des raccourcis).
        if !plugindexFrontmost {
            post(key: hotkey.keyCode, flags: hotkey.flags)
            guard await waitForPlugindex(timeout: openDelay * 3) else {
                return (false, "La fenêtre de Plugindex ne s'est pas ouverte : rien n'a été tapé. Vérifie le raccourci \(Library.openHotkey()).")
            }
            try? await Task.sleep(for: .milliseconds(openDelay))
        }
        guard plugindexFrontmost else { return (false, "Plugindex n'a plus le clavier : rien n'a été tapé.") }
        post(key: CGKeyCode(kVK_ANSI_A), flags: .maskCommand)   // remplace l'ancienne recherche
        type(name)
        try? await Task.sleep(for: .milliseconds(searchDelay))
        guard plugindexFrontmost else { return (false, "Plugindex a perdu le clavier avant Entrée : chargement annulé.") }
        post(key: CGKeyCode(kVK_Return), flags: [])
        return (true, "\(name) envoyé à Plugindex")
    }

    static var plugindexFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == plugindexBundle
    }

    private static func waitForPlugindex(timeout: Int) async -> Bool {
        var waited = 0
        while waited < timeout {
            if plugindexFrontmost { return true }
            try? await Task.sleep(for: .milliseconds(50))
            waited += 50
        }
        return plugindexFrontmost
    }

    // MARK: - Événements clavier

    private static let source = CGEventSource(stateID: .hidSystemState)

    private static func post(key: CGKeyCode, flags: CGEventFlags) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func type(_ text: String) {
        for scalar in text.utf16 {
            var unit = scalar
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}

/// Raccourci au format de Plugindex (« Control+Alt+D », « Command+Shift+P »…).
struct Hotkey {
    var keyCode: CGKeyCode
    var flags: CGEventFlags

    init?(_ text: String) {
        var flags: CGEventFlags = []
        var code: CGKeyCode?
        for part in text.split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
            switch part {
            case "control", "ctrl": flags.insert(.maskControl)
            case "alt", "option": flags.insert(.maskAlternate)
            case "command", "cmd", "commandorcontrol", "cmdorctrl": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            default: code = Hotkey.codes[part]
            }
        }
        guard let code else { return nil }
        self.keyCode = code
        self.flags = flags
    }

    private static let codes: [String: CGKeyCode] = {
        let letters: [(String, Int)] = [
            ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D), ("e", kVK_ANSI_E),
            ("f", kVK_ANSI_F), ("g", kVK_ANSI_G), ("h", kVK_ANSI_H), ("i", kVK_ANSI_I), ("j", kVK_ANSI_J),
            ("k", kVK_ANSI_K), ("l", kVK_ANSI_L), ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O),
            ("p", kVK_ANSI_P), ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R), ("s", kVK_ANSI_S), ("t", kVK_ANSI_T),
            ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X), ("y", kVK_ANSI_Y),
            ("z", kVK_ANSI_Z), ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3),
            ("4", kVK_ANSI_4), ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7), ("8", kVK_ANSI_8),
            ("9", kVK_ANSI_9), ("space", kVK_Space), ("return", kVK_Return), ("enter", kVK_Return),
        ]
        return Dictionary(uniqueKeysWithValues: letters.map { ($0.0, CGKeyCode($0.1)) })
    }()
}
