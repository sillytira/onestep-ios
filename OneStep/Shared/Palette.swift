import SwiftUI
import UIKit

enum ItemPalette: String, CaseIterable, Identifiable {
    case blue, violet, mint, amber, coral, rose
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .blue: return "drop.fill"
        case .violet: return "sparkles"
        case .mint: return "leaf.fill"
        case .amber: return "sun.max.fill"
        case .coral: return "flame.fill"
        case .rose: return "heart.fill"
        }
    }
    var color: Color {
        let light: (Double, Double, Double)
        let dark: (Double, Double, Double)
        switch self {
        case .blue: light = (0.12, 0.34, 0.83); dark = (0.43, 0.68, 1)
        case .violet: light = (0.47, 0.24, 0.76); dark = (0.76, 0.59, 1)
        case .mint: light = (0.02, 0.43, 0.32); dark = (0.32, 0.86, 0.68)
        case .amber: light = (0.65, 0.36, 0.02); dark = (1, 0.74, 0.29)
        case .coral: light = (0.77, 0.23, 0.16); dark = (1, 0.57, 0.43)
        case .rose: light = (0.70, 0.19, 0.43); dark = (1, 0.57, 0.75)
        }
        return Color(uiColor: UIColor { traits in
            let values = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: values.0, green: values.1, blue: values.2, alpha: 1)
        })
    }

    static func resolve(_ name: String?, routine: Bool = false) -> ItemPalette {
        name.flatMap(ItemPalette.init(rawValue:)) ?? (routine ? .violet : .blue)
    }
}

struct ColorBadge: View {
    let palette: ItemPalette
    let symbol: String
    var body: some View {
        Image(systemName: symbol).font(.headline)
            .foregroundStyle(palette.color)
            .frame(width: 42, height: 42)
            .background(palette.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }
}

struct PalettePicker: View {
    @Binding var selection: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Color · \(ItemPalette.resolve(selection).name)").font(.subheadline)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(ItemPalette.allCases) { palette in
                        Button { selection = palette.rawValue } label: {
                            Image(systemName: selection == palette.rawValue ? "checkmark.circle.fill" : palette.symbol)
                                .font(.title3).foregroundStyle(palette.color)
                                .frame(width: 48, height: 48)
                                .background(palette.color.opacity(selection == palette.rawValue ? 0.23 : 0.10), in: RoundedRectangle(cornerRadius: 15))
                                .overlay { RoundedRectangle(cornerRadius: 15).stroke(palette.color, lineWidth: selection == palette.rawValue ? 2 : 0) }
                        }.buttonStyle(.plain)
                            .accessibilityLabel(palette.name)
                            .accessibilityAddTraits(selection == palette.rawValue ? .isSelected : [])
                    }
                }.padding(2)
            }.scrollIndicators(.hidden)
        }.padding(.vertical, 6)
    }
}
