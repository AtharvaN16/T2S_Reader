// App/T2SReader/Design/Primitives.swift
import SwiftUI
import T2SLibrary

/// Fully rounded pill (spec §2.4.3). `.accent` is the one primary action per screen; `.selected`
/// is solid `ink` with `ground` text (chips); `.soft` and `.destructiveSoft` sit on `surface`.
struct Pill: View {
    enum Style { case soft, selected, accent, destructiveSoft }

    var label: String
    var glyph: String? = nil
    var style: Style = .soft
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let glyph { Image(systemName: glyph).font(.system(size: 13, weight: .semibold)) }
                Text(label).typeRole(.pill)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .soft: return Tokens.ink
        case .selected: return Tokens.ground
        case .accent: return Tokens.onAccent
        case .destructiveSoft: return Tokens.destructive
        }
    }

    private var background: Color {
        switch style {
        case .soft: return Tokens.surface
        case .selected: return Tokens.ink
        case .accent: return Tokens.accent
        case .destructiveSoft: return Tokens.surface
        }
    }
}

/// The section header of spec §2.4.5, shared by the pages that group rows under one — the
/// spacing below it belongs to each page, so only the type is here.
struct SectionHeader: View {
    var title: String

    var body: some View {
        Text(title).typeRole(.sectionHeader).foregroundStyle(Tokens.ink)
    }
}

/// Page title 56pt below the safe-area top, with an optional dropdown menu (spec §2.4.4).
struct PageTitle<Menu: View>: View {
    var text: String
    var subtitle: String? = nil
    @ViewBuilder var menu: () -> Menu

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(text).typeRole(.pageTitle).foregroundStyle(Tokens.ink)
                menu()
            }
            if let subtitle {
                Text(subtitle).typeRole(.meta).foregroundStyle(Tokens.ink2)
            }
        }
        .padding(.top, Spacing.titleTop)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PageTitle where Menu == EmptyView {
    init(text: String, subtitle: String? = nil) {
        self.init(text: text, subtitle: subtitle, menu: { EmptyView() })
    }
}

/// Cover artwork from a container-relative path; a `surface` block when there is none.
struct Artwork: View {
    /// SwiftUI re-evaluates a `LazyVGrid` cell's body on every scroll pass, so without this the
    /// Collection grid re-reads and re-decodes each visible cover from disk while scrolling.
    private static let cache = NSCache<NSString, UIImage>()

    var relativePath: String?
    var paths: LibraryPaths
    var size: CGFloat
    var radius: CGFloat

    /// Internal, not private: `BookCover` reads the same cache, and needs the decoded size for
    /// its proportions.
    static func image(at path: String) -> UIImage? {
        let key = path as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    var body: some View {
        Group {
            if let relativePath, let image = Self.image(at: paths.url(forRelativePath: relativePath).path) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Tokens.surface
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A book cover at its own proportions with the cues of Apple Books' Continue cell: a page block
/// behind the fore-edge, a curved-binding highlight along the spine, a soft shadow and a slight
/// turn toward the reader. Spine corners stay near-square; only the fore-edge corners round.
struct BookCover: View {
    var relativePath: String?
    var paths: LibraryPaths
    var height: CGFloat

    private var image: UIImage? {
        guard let relativePath else { return nil }
        return Artwork.image(at: paths.url(forRelativePath: relativePath).path)
    }

    /// The image's own ratio, clamped so a landscape or extreme cover cannot break the row.
    private var width: CGFloat {
        guard let image, image.size.height > 0 else { return height * 0.66 }
        return min(height * 0.85, max(height * 0.55, height * image.size.width / image.size.height))
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 1.5, bottomLeadingRadius: 1.5, bottomTrailingRadius: 5, topTrailingRadius: 5, style: .continuous)
    }

    var body: some View {
        ZStack {
            pages.offset(x: 3, y: 2)                                       // two sheets, so the fore-edge reads as a stack
            pages.offset(x: 1.5, y: 1)
            Group {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Tokens.surface
                }
            }
            .frame(width: width, height: height)
            .overlay(spine)
            .clipShape(shape)
        }
        .frame(width: width, height: height)
        .compositingGroup()                                                // one shadow for the book, not one per sheet
        .shadow(color: Tokens.ink.opacity(0.18), radius: 6, x: 2, y: 4)
        .rotation3DEffect(.degrees(-6), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.6)
        .accessibilityHidden(true)
    }

    private var pages: some View {
        shape.fill(Tokens.raised)
            .overlay(shape.stroke(Tokens.ink3, lineWidth: 1))
            .frame(width: width, height: height)
    }

    /// The classic curved binding: dark in the gutter, a thin bright ridge, then the cover.
    private var spine: some View {
        LinearGradient(stops: [
            .init(color: Tokens.ink.opacity(0.28), location: 0),
            .init(color: Tokens.raised.opacity(0.22), location: 0.09),
            .init(color: Tokens.raised.opacity(0), location: 0.18),
        ], startPoint: .leading, endPoint: .trailing)
    }
}

/// Thin progress line under covers and chapter rows.
struct ProgressBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.ink3)
                Capsule().fill(Tokens.ink).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 2)
    }
}

/// A ring showing elapsed fraction of a document (Continue Listening row).
struct CircularProgress: View {
    var fraction: Double
    var lineWidth: CGFloat = 3
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle().stroke(Tokens.ink3, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(Tokens.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A pulsing accent dot for the one-time voice warm-up — visually distinct from the routine
/// buffering spinner (`ProgressView`) so a reader can tell "this is the long one-time wait" from
/// "this resolves in a second or two." Respects Reduce Motion with a static dot instead of a loop.
struct WarmingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bright = false

    var body: some View {
        Circle()
            .fill(Tokens.accent)
            .frame(width: 10, height: 10)
            .opacity(bright ? 1 : 0.35)
            // Conditioned on `reduceMotion` here, not inside `onAppear`, so a live toggle of the
            // setting (Control Center, during the up-to-minutes warm-up this represents) takes
            // effect immediately rather than only at the next time this view appears.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: bright)
            .onAppear { bright = true }
            .accessibilityHidden(true)
    }
}

/// The `positive` check that means "ready": plays with no synthesis and no network (spec §3.4.1).
struct PositiveCheck: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 16))
            .foregroundStyle(Tokens.positive)
            .accessibilityLabel("Ready to play offline")
    }
}
