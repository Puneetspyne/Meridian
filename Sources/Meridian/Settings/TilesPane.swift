import SwiftUI
import MeridianKit

struct TilesPane: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(model.settings.tiles) { tile in
                        HStack {
                            Toggle(tile.label, isOn: visible(tile))
                                .toggleStyle(.switch)
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .accessibilityHint("Drag to reorder")
                    }
                    .onMove { model.settings.tiles.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Drag to set the order the card shows them in. Switched-off tiles stay out of the card.")
                        .padding(.top, 6)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Divider()
            HStack {
                Spacer()
                Button("Restore defaults") {
                    model.settings.tiles = Tile.defaultOrder
                    model.settings.hiddenTiles = Settings().hiddenTiles
                }
                .disabled(model.settings.tiles == Tile.defaultOrder && model.settings.hiddenTiles == Settings().hiddenTiles)
            }
            .padding(12)
        }
    }

    private func visible(_ tile: Tile) -> Binding<Bool> {
        Binding(
            get: { !model.settings.hiddenTiles.contains(tile) },
            set: { on in
                if on { model.settings.hiddenTiles.remove(tile) } else { model.settings.hiddenTiles.insert(tile) }
            })
    }
}
