// App/T2SReader/Onboarding/ReferralPage.swift
import SwiftUI
import T2SApp

/// The welcome's fifth screen: somewhere to put a referral code, and the scheme it belongs to (the
/// owner, 2026-09-18: "then referall page", and "if you refer four friends, you get one month of
/// pro for free").
///
/// **Nothing is redeemed here.** Like the two screens either side of it, this is a mock-up: the
/// code is held in `code` and goes nowhere, because there is no account for it to belong to yet.
/// What the screen has to get right today is the *offer* — how many friends, and what they earn —
/// which is `ProOffer.referralsForFreeMonth` rather than a number typed into a sentence.
///
/// The field is optional and the key says so. A required code on a screen with nothing behind it
/// would be a wall with no door.
struct ReferralPage: View {
    var offer: ProOffer
    var onContinue: (String?) -> Void

    @State private var code = ""
    @FocusState private var isTyping: Bool

    private var trimmed: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image(systemName: "gift.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(Tokens.accent)
                .padding(.bottom, Spacing.row)

            Text("Were you invited?")
                .typeRole(.pageTitle)
                .foregroundStyle(Tokens.ink)
                .multilineTextAlignment(.center)

            Text("Put your friend's code in and you both get a month of Pro.")
                .typeRole(.rowTitle)
                .foregroundStyle(Tokens.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Spacing.grid + 2)

            TextField("Referral code", text: $code)
                .typeRole(.rowTitle)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($isTyping)
                .submitLabel(.done)
                .onSubmit { isTyping = false }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tokens.surface))
                .padding(.top, Spacing.row)

            // The scheme itself, stated once and taken from the offer rather than written into the
            // sentence — a screen that quotes its own terms wrongly is worse than one that omits
            // them.
            Text("Invite \(offer.referralsForFreeMonth) friends to T2S and you get a month of Pro, free.")
                .typeRole(.meta)
                .foregroundStyle(Tokens.ink2)
                .multilineTextAlignment(.center)
                .padding(.top, Spacing.row)
                .padding(.horizontal, Spacing.grid)

            Spacer(minLength: 0)

            RaisedButton(label: trimmed.isEmpty ? "I don't have one" : "Apply code",
                         tone: trimmed.isEmpty ? .ink : .blue,
                         size: .bar) {
                isTyping = false
                onContinue(trimmed.isEmpty ? nil : trimmed)
            }
            .animation(.snappy, value: trimmed.isEmpty)
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.bottom, Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { isTyping = false }
    }
}
