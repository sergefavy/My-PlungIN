import SwiftUI

/// Choisir un plugin de ta bibliothèque pour en faire un bouton.
struct PluginPicker: View {
    @Environment(Bridge.self) private var bridge
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var kind = "Tous"
    let pick: (PluginInfo) -> Void

    private var filtered: [PluginInfo] {
        bridge.library.filter { plugin in
            (kind == "Tous" || plugin.kind == kind) &&
            (search.isEmpty || plugin.name.localizedCaseInsensitiveContains(search) || plugin.maker.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Type", selection: $kind) {
                    ForEach(["Tous", "Instrument", "Effet"], id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if !search.isEmpty {
                    Button("Ajouter « \(search) » tel quel", systemImage: "text.cursor") {
                        pick(PluginInfo(key: "libre~" + search.lowercased(), name: search, maker: "", kind: "", hasImage: false))
                        dismiss()
                    }
                }
                ForEach(filtered) { plugin in
                    Button {
                        pick(plugin)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Group {
                                if let image = bridge.image(for: plugin.key) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                } else {
                                    Image(systemName: plugin.kind == "Instrument" ? "pianokeys" : "slider.vertical.3")
                                        .foregroundStyle(Theme.gold)
                                }
                            }
                            .frame(width: 44, height: 44)
                            .background(Theme.wallDark)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading) {
                                Text(plugin.name).foregroundStyle(Theme.cream)
                                Text(plugin.maker.isEmpty ? plugin.kind : "\(plugin.maker) · \(plugin.kind)")
                                    .font(.caption).foregroundStyle(Theme.cream.opacity(0.6))
                            }
                        }
                    }
                    .listRowBackground(Theme.wall.opacity(0.6))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .searchable(text: $search, prompt: "Chercher un plugin")
            .navigationTitle("Ajouter un bouton")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
    }
}

/// Modifier un bouton : nom, texte cherché dans Plugindex, couleur, image, place.
struct PadEditor: View {
    @Environment(Layout.self) private var layout
    @Environment(Bridge.self) private var bridge
    @Environment(\.dismiss) private var dismiss
    @State var pad: Pad
    let pageIndex: Int

    private var position: Int? { layout.pages[pageIndex].pads.firstIndex { $0.id == pad.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bouton") {
                    TextField("Nom affiché", text: $pad.label)
                    TextField("Texte cherché dans Plugindex", text: $pad.searchName)
                        .textInputAutocapitalization(.never)
                    Toggle("Montrer l'image du plugin", isOn: $pad.showImage)
                }
                Section("Couleur") {
                    HStack {
                        ForEach(Layout.palette, id: \.self) { hex in
                            Circle().fill(Color(hex: hex)).frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(.white, lineWidth: pad.colorHex == hex ? 3 : 0))
                                .onTapGesture { pad.colorHex = hex }
                        }
                    }
                }
                Section("Place") {
                    HStack {
                        Button("Avant", systemImage: "arrow.left") { move(-1) }
                        Spacer()
                        Button("Après", systemImage: "arrow.right") { move(1) }
                    }
                    .buttonStyle(.borderless)
                    Menu("Déplacer vers une autre page") {
                        ForEach(layout.pages.indices.filter { $0 != pageIndex }, id: \.self) { index in
                            Button(layout.pages[index].name) {
                                guard let position else { return }
                                layout.pages[pageIndex].pads.remove(at: position)
                                layout.pages[index].pads.append(pad)
                                dismiss()
                            }
                        }
                    }
                }
                Section {
                    Button("Essayer") { bridge.load(pad.searchName) }
                    Button("Supprimer le bouton", role: .destructive) {
                        if let position { layout.pages[pageIndex].pads.remove(at: position) }
                        dismiss()
                    }
                }
            }
            .navigationTitle(pad.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        if let position { layout.pages[pageIndex].pads[position] = pad }
                        dismiss()
                    }
                }
            }
        }
    }

    private func move(_ offset: Int) {
        guard let position else { return }
        let target = position + offset
        guard layout.pages[pageIndex].pads.indices.contains(target) else { return }
        layout.pages[pageIndex].pads[position] = pad
        layout.pages[pageIndex].pads.swapAt(position, target)
    }
}

/// Réglages d'une page : nom, colonnes, page de la montre, suppression.
struct PageSettings: View {
    @Environment(Layout.self) private var layout
    @Environment(\.dismiss) private var dismiss
    let pageIndex: Int
    let deleted: () -> Void

    var body: some View {
        NavigationStack {
            if layout.pages.indices.contains(pageIndex) { form(layout) }
        }
    }

    private func form(_ layout: Layout) -> some View {
        @Bindable var layout = layout
        return Form {
                Section("Page") {
                    TextField("Nom", text: $layout.pages[pageIndex].name)
                    Stepper("Colonnes : \(layout.pages[pageIndex].columns)", value: $layout.pages[pageIndex].columns, in: 1...8)
                }
                Section {
                    Toggle("Page de l'Apple Watch", isOn: Binding(
                        get: { layout.watchPage?.id == layout.pages[pageIndex].id },
                        set: { if $0 { layout.watchPageID = layout.pages[pageIndex].id } }
                    ))
                } footer: {
                    Text("Les boutons de cette page apparaissent sur ta montre.")
                }
                if layout.pages.count > 1 {
                    Section {
                        Button("Supprimer la page", role: .destructive) {
                            dismiss()
                            layout.pages.remove(at: pageIndex)
                            deleted()
                        }
                    }
                }
            }
            .navigationTitle("Réglages de la page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
    }
}
