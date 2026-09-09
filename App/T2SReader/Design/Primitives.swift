// App/T2SReader/Design/Primitives.swift
import SwiftUI
import T2SLibrary

/// Fully rounded pill (spec §2.4.3). `.accent` is the one primary action per screen; `.selected`
/// is solid `ink` with `ground` text (chips); `.soft` and `.destructiveSoft` sit on `surface`.
struct Pill: View {
    enum Style { case soft, selected, accent, destructiveSoft }

    var label: String
    /// A quieter second word after the label — the Play pill's "2h 28m" — in the same type, dimmed.
    var detail: String? = nil
    var glyph: String? = nil
    var style: Style = .soft
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let glyph { Image(systemName: glyph).font(.system(size: 13, weight: .semibold)) }
                Text(label).typeRole(.pill)
                if let detail { Text(detail).typeRole(.pill).foregroundStyle(foreground.opacity(0.55)) }
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

/// The book of Figma's "6 Elegant Book Mockups" no. 3 (node 10:6366), at row size: a softcover lying
/// flat and seen straight on — square spine corners, softly rounded fore-edge corners, a hinge crease
/// a few points in from the spine, a soft shadow cast down and to the right, and a faint sheen. The
/// mockup's paper texture and blurred-scene shadow are its own raster layers; at 112 pt they are
/// invisible, so the shadow is SwiftUI's and the texture is left out.
///
/// Covers only look like covers at book proportions: an image narrower than 0.55 or wider than 0.8
/// of its height (a landscape, a banner, a page scan) and a document with no image both get the
/// placeholder — the title on a plain cover — and every PDF gets a light red one that says PDF.
struct BookCover: View {
    var relativePath: String?
    var paths: LibraryPaths
    var height: CGFloat
    var title: String
    var isPDF: Bool = false

    /// The mockup's own proportions (1461 × 2192); a real cover uses its own, within the book range.
    private static let ratio: CGFloat = 0.667
    private static let coverRatios: ClosedRange<CGFloat> = 0.55...0.8

    private var image: UIImage? {
        guard !isPDF, let relativePath,
              let image = Artwork.image(at: paths.url(forRelativePath: relativePath).path),
              image.size.height > 0, Self.coverRatios.contains(image.size.width / image.size.height)
        else { return nil }
        return image
    }

    private var width: CGFloat {
        guard let image else { return height * Self.ratio }
        return height * image.size.width / image.size.height
    }

    private var shape: UnevenRoundedRectangle {
        let r = height * 0.03
        return UnevenRoundedRectangle(topLeadingRadius: 1, bottomLeadingRadius: 1, bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
    }

    var body: some View {
        face
            .frame(width: width, height: height)
            .overlay(hinge)
            .overlay(sheen)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Tokens.shade.opacity(0.12), lineWidth: 0.5))
            .compositingGroup()                                                // one shadow for the book, not one per layer
            .shadow(color: Tokens.shade.opacity(0.22), radius: height * 0.06, x: height * 0.015, y: height * 0.045)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var face: some View {
        if let image {
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
        } else if isPDF {
            Tokens.pdfCover.overlay {
                Text("PDF").typeRole(.sectionHeader).foregroundStyle(Tokens.pdfInk).minimumScaleFactor(0.5).padding(8)
            }
        } else {
            // The mockup's title band across the lower third, on a plain cover.
            Tokens.surface.overlay(alignment: .bottom) {
                Text(title)
                    .typeRole(.meta).foregroundStyle(Tokens.ink)
                    .lineLimit(2).minimumScaleFactor(0.7).multilineTextAlignment(.center)
                    .padding(.horizontal, 6).padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Tokens.ground)
                    .padding(.bottom, height * 0.12)
            }
        }
    }

    /// The softcover's hinge: a bright sliver at the spine edge, a darker crease just inside it.
    private var hinge: some View {
        LinearGradient(stops: [
            .init(color: Tokens.gloss.opacity(0.18), location: 0),
            .init(color: Tokens.shade.opacity(0), location: 0.015),
            .init(color: Tokens.shade.opacity(0.16), location: 0.035),
            .init(color: Tokens.shade.opacity(0), location: 0.08),
        ], startPoint: .leading, endPoint: .trailing)
    }

    /// The mockup's two reflection layers: a little light from the top-left, a little more at the foot.
    private var sheen: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: Tokens.gloss.opacity(0.10), location: 0),
                .init(color: Tokens.gloss.opacity(0), location: 0.45),
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(stops: [
                .init(color: Tokens.gloss.opacity(0), location: 0.6),
                .init(color: Tokens.gloss.opacity(0.07), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
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
