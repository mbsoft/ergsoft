import SwiftUI

/// ErgSoft's own rower mark (vector template asset) — tints like an SF Symbol.
struct RowerGlyph: View {
    var size: CGFloat = 22
    var body: some View {
        Image("RowerGlyph").renderingMode(.template).resizable().scaledToFit()
            .frame(width: size, height: size)
    }
}
