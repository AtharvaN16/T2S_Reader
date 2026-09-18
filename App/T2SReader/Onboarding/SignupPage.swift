// App/T2SReader/Onboarding/SignupPage.swift
import SwiftUI
import T2SApp

/// The welcome's fourth screen: an offer to keep the library, and a way past it (the owner,
/// 2026-09-18: "we need to show the signup page", with Queue's own welcome as the reference).
///
/// **It signs nobody in.** The 2026-09-14 design decided there would be no auth in this flow and
/// the owner reaffirmed it on 2026-09-18: this is a mock-up that only continues. The Apple key is
/// drawn, not wired — no `AuthenticationServices`, no entitlement, no account. When it is wired,
/// the only thing here that changes is what `onSignIn` does.
///
/// **"Not now" is a peer of the key, not a footnote.** A reader who does not want an account should
/// not have to hunt for the way past — which is the dark pattern the paywall two screens on
/// explicitly promises not to use, and it would be odd to commit that here and break it there.
struct SignupPage: View {
    var onSignIn: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image(systemName: "books.vertical.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Tokens.glow)
                .padding(.bottom, Spacing.row)

            Text("Keep your library")
                .typeRole(.pageTitle)
                .foregroundStyle(Tokens.ink)
                .multilineTextAlignment(.center)

            Text("Your books, your place in them and your bookmarks follow you to your other devices.")
                .typeRole(.rowTitle)
                .foregroundStyle(Tokens.ink2)
                .multilineTextAlignment(.center)
                // Without this a `Text` in a `VStack` between two `Spacer`s is offered two lines
                // and truncates the third — the first photograph ended "…follow you to your…".
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Spacing.grid + 2)
                .padding(.horizontal, Spacing.grid)

            Spacer(minLength: 0)

            RaisedButton(label: "Sign in with Apple", glyph: "apple.logo", tone: .ink, size: .bar, action: onSignIn)

            Button("Not now", action: onSkip)
                .typeRole(.pill)
                .foregroundStyle(Tokens.ink2)
                .padding(.top, Spacing.row)
                .accessibilityHint("Continue without an account")
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.bottom, Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
