// App/T2SReader/Preferences/HowItWorksSheet.swift
import SwiftUI
import T2SApp

/// Settings → About → "How it works": four short answers to the questions the app otherwise
/// answers by surprise — why the phone is warm, why a chapter you have heard once starts at
/// instantly, what the voice can and cannot do, and where any of it goes.
///
/// The words are `HowItWorks` in T2SApp, where their length is held to by a test. This file is the
/// drawing alone: a glyph column, a title, a line or two, four times.
struct HowItWorksSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        Text("How it works")
                            .typeRole(.playerTitle).foregroundStyle(Tokens.ink)
                        Spacer(minLength: 12)
                        Button { dismiss() } label: { CircleGlyph(systemName: "xmark") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close")
                    }
                    // `.lineLimit(nil)` is not redundant, and it has to sit *inside* `typeRole`:
                    // the `.rowTitle` role puts a limit of 2 in the environment for rows that are
                    // rows, and this is a sentence. Without it the sheet opens on an ellipsis.
                    Text(HowItWorks.lead)
                        .lineLimit(nil)
                        .typeRole(.rowTitle).foregroundStyle(Tokens.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(HowItWorks.points) { point in
                        HowItWorksRow(point: point)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.margin)
            .padding(.top, 32)
            .padding(.bottom, Spacing.section)
        }
        .scrollIndicators(.hidden)
        .presentationBackground(Tokens.ground)
        // Sized to the four points, not to a stock detent. `.medium` is half the screen and cut
        // the last point off mid-title, which is the one arrangement worse than either extreme —
        // a reader who does not drag never learns there was a fourth. `.large` for half a screen
        // of text reads as a page you have been navigated to rather than a thing you read and
        // dismiss. The fraction is what the content actually comes to at the default text size;
        // at the accessibility sizes it overflows and the sheet scrolls, which is why the scroll
        // view stays.
        .presentationDetents([.fraction(0.72), .large])
        .presentationCornerRadius(Spacing.sheetCorner)
    }
}

/// One point: the glyph in its own column so the titles and their lines share a left edge, the way
/// the rows of a settings group do.
private struct HowItWorksRow: View {
    var point: HowItWorks.Point

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Aligned to the title's line rather than centred on the block: a glyph that floats
            // halfway down a paragraph reads as belonging to no line in particular.
            Image(systemName: point.symbol)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(Tokens.ink)
                .frame(width: 26, height: 22, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(point.title)
                    .typeRole(.sectionHeader).foregroundStyle(Tokens.ink)
                Text(point.body)
                    .typeRole(.meta).foregroundStyle(Tokens.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
