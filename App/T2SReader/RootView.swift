import SwiftUI

/// Placeholder until Task 6 brings the pager. Proves the bundled fonts load: the title must render
/// in Inter Display Black, not the system font.
struct RootView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("t2s")
                .font(.custom("InterDisplay-Black", size: 34))
            Text("Fonts loaded: \(UIFont.fontNames(forFamilyName: "Inter Display").sorted().joined(separator: ", "))")
                .font(.custom("Inter-Regular", size: 13))
            Spacer()
        }
        .padding(24)
    }
}
