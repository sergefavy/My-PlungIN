import SwiftUI

/// Couleurs de la maquette validée : bordeaux pastel, crème, accent doré.
enum Theme {
    static let wall = Color(hex: "7A5A62")
    static let wallDark = Color(hex: "5E434A")
    static let cream = Color(hex: "E9D3D7")
    static let creamShade = Color(hex: "DCC0C6")
    static let accent = Color(hex: "9B4A5C")
    static let ink = Color(hex: "3A1F27")
    static let gold = Color(hex: "D6B36A")

    /// Fond « papier peint » : dégradé bordeaux avec un léger motif.
    static var background: some View {
        LinearGradient(colors: [wall, wallDark], startPoint: .top, endPoint: .bottom)
            .overlay(
                Canvas { context, size in
                    let step: CGFloat = 22
                    var y: CGFloat = 0
                    while y < size.height {
                        var x: CGFloat = (Int(y / step) % 2 == 0) ? 0 : step / 2
                        while x < size.width {
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.2, height: 2.2)), with: .color(.white.opacity(0.06)))
                            x += step
                        }
                        y += step
                    }
                }
            )
            .ignoresSafeArea()
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
