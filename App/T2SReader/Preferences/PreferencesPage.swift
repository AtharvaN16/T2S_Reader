// App/T2SReader/Preferences/PreferencesPage.swift  (content arrives in Plan 4b)
import SwiftUI

struct PreferencesPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            PageTitle(text: "Preferences")
            Text("Voice, playback, reading, pronunciation, and storage settings arrive with the Reader.")
                .typeRole(.meta)
                .foregroundStyle(Tokens.ink2)
            Spacer()
        }
        .padding(.horizontal, Spacing.margin)
        .background(Tokens.ground)
    }
}
