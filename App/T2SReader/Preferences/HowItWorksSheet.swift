// App/T2SReader/Preferences/HowItWorksSheet.swift
import SwiftUI
import T2SApp

/// Settings → About → "How the app works": the sheet that answers the questions the app otherwise
/// answers by surprise — why the phone is warm, why the first launch downloads 620 MB, why a
/// chapter you have heard once starts instantly and a new one takes a moment, and what of all this
/// ever leaves the device.
///
/// Every one of those has a line of its own somewhere in the app already — the warm hold's card,
/// Storage's delete warning, the sync row's subtitle — but each is only met at the moment it bites,
/// and only by the reader it bit. This is the one place they can be read before anything goes
/// wrong, which is the whole point of it.
///
/// The words are not here; they are `HowItWorks` in T2SApp, where they can be tested on the Mac.
/// This file is the drawing alone: a glyph column, a line, a paragraph, six times.
struct HowItWorksSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    /// The sheet is built for the build it is running in: the everyday one has no model to fetch,
    /// so it is not told the size of one.
    private var hasOnDeviceVoice: Bool { env.kokoroModel.isSupported }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        Text("How the app works")
                            .typeRole(.playerTitle).foregroundStyle(Tokens.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        Button { dismiss() } label: { CircleGlyph(systemName: "xmark") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close")
                    }
                    // `.lineLimit(nil)` is not redundant, and it has to sit *inside* `typeRole`:
                    // the `.rowTitle` role puts a limit of 2 in the environment for rows that are
                    // rows, and the lead is a paragraph. Without it the sheet opens on a summary
                    // that ends in an ellipsis.
                    Text(HowItWorks.lead(hasOnDeviceVoice: hasOnDeviceVoice))
                        .lineLimit(nil)
                        .typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 28 between points, not the 40 of a Settings section: these are one list read
                // straight down, and a section's worth of air between each turns six paragraphs
                // into six screens.
                VStack(alignment: .leading, spacing: Spacing.row) {
                    ForEach(HowItWorks.points(hasOnDeviceVoice: hasOnDeviceVoice)) { point in
                        HowItWorksRow(point: point)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.margin)
            .padding(.top, Spacing.section)
            .padding(.bottom, Spacing.section)
        }
        .scrollIndicators(.hidden)
        .presentationBackground(Tokens.ground)
        .presentationDetents([.large])
        .presentationCornerRadius(Spacing.sheetCorner)
    }
}

/// One point: the glyph in its own column so the titles and their paragraphs share a left edge,
/// the way the rows of a settings group do.
private struct HowItWorksRow: View {
    var point: HowItWorks.Point

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Aligned to the title's cap height rather than centred on the block: a glyph that
            // floats halfway down a four-line paragraph reads as belonging to no line in particular.
            Image(systemName: point.symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Tokens.ink)
                .frame(width: 28, height: 24, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(point.title)
                    .typeRole(.groupTitle).foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(point.body)
                    .typeRole(.meta).foregroundStyle(Tokens.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
