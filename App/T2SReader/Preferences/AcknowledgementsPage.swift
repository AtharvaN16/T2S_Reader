// App/T2SReader/Preferences/AcknowledgementsPage.swift
import SwiftUI

/// Settings → About → Acknowledgements (owner, 2026-09-18): the open-source work the app is built
/// on, each with its licence. This was one line at the foot of About, drawn as a row with a chevron
/// that did nothing; a page is the one shape a list of names can be read in.
///
/// The register behind it is `docs/licenses.md`; these are the components a reader meets — the
/// type, the book engine, the article extractor — not the libraries those pull in.
struct AcknowledgementsPage: View {
    private struct Credit: Identifiable {
        let name: String
        let role: String
        let licence: String
        var id: String { name }
    }

    private let credits: [Credit] = [
        Credit(name: "Inter", role: "The type", licence: "SIL Open Font License 1.1"),
        Credit(name: "Readium", role: "Reads the books", licence: "BSD-3-Clause"),
        Credit(name: "Readability", role: "Extracts the articles", licence: "Apache-2.0"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                PageTitle(text: "Acknowledgements", topPadding: Spacing.subpageTitleTop)
                SettingsGroup {
                    ForEach(Array(credits.enumerated()), id: \.element.id) { index, credit in
                        SettingsGroupRow(title: credit.name, subtitle: credit.role,
                                         value: credit.licence, separator: index > 0)
                    }
                }
                Text("Built with open-source software. The full register, with every library these depend on, is in the app's repository.")
                    .typeRole(.meta).foregroundStyle(Tokens.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Color.clear.frame(height: Spacing.bottomClearance)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .settingsSubpage()
    }
}
