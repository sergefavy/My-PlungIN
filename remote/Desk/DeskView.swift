import SwiftUI

/// Le desk : des pages de boutons que tu composes toi-même.
struct DeskView: View {
    @Environment(Bridge.self) private var bridge
    @Environment(Layout.self) private var layout
    @State private var pageID: UUID?
    @State private var editing = false
    @State private var picking = false
    @State private var editingPad: Pad?
    @State private var pageSettings = false

    private var pageIndex: Int {
        layout.pages.firstIndex { $0.id == pageID } ?? 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                pageBar
                ScrollView {
                    let page = layout.pages[pageIndex]
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: max(1, page.columns)), spacing: 14) {
                        ForEach(page.pads) { pad in
                            PadButton(pad: pad, image: pad.showImage ? bridge.image(for: pad.pluginKey) : nil, editing: editing) {
                                if editing { editingPad = pad } else { bridge.load(pad.searchName) }
                            }
                        }
                        if editing {
                            Button { picking = true } label: {
                                RoundedRectangle(cornerRadius: 18)
                                    .strokeBorder(Theme.cream.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8]))
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay(Image(systemName: "plus").font(.largeTitle))
                            }
                        }
                    }
                    .padding(16)
                    if page.pads.isEmpty && !editing {
                        Text("Page vide. Touche « Modifier » pour ajouter tes plugins.")
                            .font(.callout).opacity(0.7).padding(.top, 40)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle(bridge.macName ?? "Desk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Réglages de la page", systemImage: "slider.horizontal.3") { pageSettings = true }
                        Button("Nouvelle page", systemImage: "plus.rectangle.on.rectangle") {
                            layout.pages.append(Page(name: "Page \(layout.pages.count + 1)"))
                            pageID = layout.pages.last?.id
                        }
                        Button("Recharger la bibliothèque", systemImage: "arrow.clockwise") { bridge.refreshLibrary() }
                        Divider()
                        Button("Oublier ce Mac", systemImage: "xmark.circle", role: .destructive) { bridge.unpair() }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing ? "OK" : "Modifier") { withAnimation { editing.toggle() } }.bold()
                }
            }
            .sheet(isPresented: $picking) {
                PluginPicker { plugin in layout.add(plugin, to: layout.pages[pageIndex].id) }
            }
            .sheet(item: $editingPad) { pad in
                PadEditor(pad: pad, pageIndex: pageIndex)
            }
            .sheet(isPresented: $pageSettings) {
                PageSettings(pageIndex: pageIndex) { pageID = layout.pages.first?.id }
            }
        }
    }

    private var pageBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(layout.pages) { page in
                    let selected = page.id == layout.pages[pageIndex].id
                    Button { pageID = page.id } label: {
                        HStack(spacing: 4) {
                            if page.id == layout.watchPage?.id { Image(systemName: "applewatch").font(.caption2) }
                            Text(page.name)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .foregroundStyle(selected ? Theme.ink : Theme.cream)
                        .background(selected ? Theme.cream : Theme.wallDark, in: Capsule())
                        .shadow(color: .black.opacity(0.3), radius: selected ? 3 : 0, y: 2)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
}

/// Un bouton bombé, façon pastille crème de la maquette.
struct PadButton: View {
    let pad: Pad
    let image: UIImage?
    let editing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: [Color(hex: pad.colorHex).opacity(0.95), Color(hex: pad.colorHex).opacity(0.7)],
                                         startPoint: .top, endPoint: .bottom))
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                                    .clipShape(RoundedRectangle(cornerRadius: 18)))
                }
                Text(pad.label)
                    .font(.headline).lineLimit(2).minimumScaleFactor(0.7)
                    .foregroundStyle(.white).shadow(radius: 2)
                    .padding(10)
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if editing {
                    Image(systemName: "pencil.circle.fill").font(.title2).foregroundStyle(Theme.gold).padding(6)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 6, y: 4)
            .rotationEffect(.degrees(editing ? 1.2 : 0))
        }
        .buttonStyle(PressStyle())
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
    }
}
