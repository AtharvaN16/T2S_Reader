// App/T2SReader/Root/PageIndicator.swift
import SwiftUI

struct PageIndicator: View {
    @Binding var page: RootPage

    var body: some View {
        HStack(spacing: 28) {
            ForEach(RootPage.allCases, id: \.self) { p in
                Button {
                    withAnimation(.snappy) { page = p }
                } label: {
                    Image(systemName: p.glyph)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(p == page ? Tokens.ink : Tokens.ink3)
                        .frame(width: 44, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(p.title)
                .accessibilityAddTraits(p == page ? .isSelected : [])
            }
        }
    }
}
