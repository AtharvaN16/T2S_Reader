// App/T2SReader/Design/FilterTabs.swift
import SwiftUI

/// A row of kind tabs: words, the chosen one in ink with a short bar under it, the rest dimmed.
/// Replaced the Collection's pill chips (owner, 2026-09-09): a row of pills under a Search pill
/// read as more buttons, not as a filter — a pill is what this app presses. Tabs under the header
/// are what a library filters by (Apple Music's Library, Podcasts' show pages). The bar slides
/// between words. Scrolls rather than wraps at the large text sizes, as the chips did.
struct FilterTabs<Option: Hashable>: View {
    var options: [Option]
    var title: (Option) -> String
    @Binding var selection: Option
    @Namespace private var bar

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(options, id: \.self) { option in
                    let isOn = option == selection
                    Button {
                        withAnimation(.snappy) { selection = option }
                    } label: {
                        Text(title(option))
                            .typeRole(.pill)
                            .foregroundStyle(isOn ? Tokens.ink : Tokens.ink2)
                            .padding(.vertical, 9)
                            .overlay(alignment: .bottom) {
                                if isOn {
                                    Capsule().fill(Tokens.ink).frame(height: 2)
                                        .matchedGeometryEffect(id: "bar", in: bar)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? [.isSelected] : [])
                }
            }
        }
    }
}
