// App/T2SReader/Design/Primitives.swift
import CoreImage
import CoreImage.CIFilterBuiltins
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

/// The 36 pt `surface` circle with one 15 pt semibold glyph in it: the page headers' `+`, the rows'
/// `⋯`, the Reader bar's circles. A label, not a button, so a `Button` and a `Menu` can both wear it.
struct CircleGlyph: View {
    var systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Tokens.ink)
            .frame(width: 36, height: 36)
            .background(Tokens.surface, in: Circle())
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

/// The one action of a step, as a full-width bar pinned to a page's foot (ElevenReader's "Listen",
/// Uptime's "Select voice" — the owner's references, 2026-09-09/10): ink when it can be pressed,
/// `surface` and `ink2` while there is nothing to act on, a spinner and `busyLabel` while the model
/// works. Pages pin it with `safeAreaInset(edge: .bottom)` so it rides above the keyboard.
struct BarButton: View {
    var label: String
    var busyLabel: String? = nil
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        let busy = busyLabel != nil
        let enabled = isEnabled && !busy
        Button(action: action) {
            HStack(spacing: 10) {
                if busy { ProgressView().tint(Tokens.ink2) }
                Text(busyLabel ?? label).typeRole(.rowTitle)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .foregroundStyle(enabled ? Tokens.ground : Tokens.ink2)
            .background(enabled ? Tokens.ink : Tokens.surface, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(.snappy, value: enabled)
    }
}

/// A radio mark: the empty ring of a choice not taken, or an ink disc with a check for the one
/// that is (Beside's voice list, the owner's reference, 2026-09-10). Visual only — the row it sits
/// in is the button — so a list of them reads as "pick one" before anything is tapped.
struct RadioMark: View {
    var isOn: Bool

    var body: some View {
        ZStack {
            if isOn {
                Circle().fill(Tokens.ink)
                Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Tokens.ground)
            } else {
                Circle().strokeBorder(Tokens.ink2, lineWidth: 2)             // the heart outline's weight, so the two marks match
            }
        }
        .frame(width: 24, height: 24)
        .animation(.snappy, value: isOn)
        .accessibilityHidden(true)
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
    /// Degrees from `MotionTilt`: the book turns a little with the phone so it reads as an object,
    /// not a picture. Only the book sheet's hero passes one.
    var tilt: CGPoint = .zero

    /// The mockup's own proportions (1461 × 2192); a real cover uses its own, within the book range.
    /// Internal, not private: the book sheet's hero sizes from it.
    static let ratio: CGFloat = 0.667
    private static let coverRatios: ClosedRange<CGFloat> = 0.55...0.8
    /// The widest a real cover is allowed to be (`coverRatios.upperBound`): the width of a
    /// `shelved` slot, so no cover ever has to shrink to fit one.
    static let widestRatio: CGFloat = coverRatios.upperBound
    /// The one height a book stands at on Home and in the Collection grid (owner, 2026-09-09: the
    /// same book looked a different size on the two pages — the grid's height came from its column
    /// width, Home's was 112). One constant, not a derived one, so it matches across pages and phones.
    static let shelfHeight: CGFloat = 120

    /// The book on a shelf: a slot `widestRatio` wide and `height` tall with the book at its
    /// bottom-leading corner. Covers keep their own proportions — a wide cover cropped loses its
    /// lettering, padded looks broken — so a row of them can only be made to read as one by giving
    /// every book the same slot: a shared baseline, a shared left edge for the text beside or
    /// under it, and only the fore-edge moving. Apple Books, Kindle and Libby shelve the same way.
    var shelved: some View {
        frame(width: height * Self.widestRatio, height: height, alignment: .bottomLeading)
    }

    private var image: UIImage? {
        guard !isPDF, let relativePath,
              let image = Artwork.image(at: paths.url(forRelativePath: relativePath).path),
              image.size.height > 0, Self.coverRatios.contains(image.size.width / image.size.height)
        else { return nil }
        return image
    }

    /// The book's frame: `height` tall at its own proportions.
    private var size: CGSize {
        let ratio = image.map { $0.size.width / $0.size.height } ?? Self.ratio
        return CGSize(width: height * ratio, height: height)
    }

    private func shape(_ height: CGFloat) -> UnevenRoundedRectangle {
        let r = height * 0.03
        return UnevenRoundedRectangle(topLeadingRadius: 1, bottomLeadingRadius: 1, bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
    }

    var body: some View {
        let size = size
        let shape = shape(size.height)
        face(height: size.height)
            .frame(width: size.width, height: size.height)
            .overlay(hinge)
            .overlay(sheen)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Tokens.shade.opacity(0.12), lineWidth: 0.5))
            .compositingGroup()                                                // one shadow for the book, not one per layer
            .shadow(color: Tokens.shade.opacity(0.22), radius: size.height * 0.06,
                    x: size.height * 0.015 + tilt.x * 0.45, y: size.height * 0.045 + tilt.y * 0.45)   // the shadow leans with the book
            .rotation3DEffect(.degrees(tilt.x), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(-tilt.y), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .accessibilityHidden(true)
    }

    /// The colour the book gives off — the book sheet's backlight: the cover's average colour,
    /// lifted so a dark or greyish cover still glows; the PDF book's red; the placeholder's paper.
    var backlight: Color {
        if let image, let average = Self.averageColor(of: image, key: relativePath ?? "") { return average }
        return isPDF ? Tokens.pdfCover : Tokens.ink3
    }

    private static let colorCache = NSCache<NSString, UIColor>()
    private static let colorContext = CIContext(options: [.workingColorSpace: NSNull()])

    /// One `CIAreaAverage` per cover, cached by path (the decode is the expensive part and
    /// `Artwork` already caches that; this is a 1 × 1 render on top).
    private static func averageColor(of image: UIImage, key: String) -> Color? {
        let cacheKey = key as NSString
        if let hit = colorCache.object(forKey: cacheKey) { return Color(hit) }
        guard let input = CIImage(image: image) else { return nil }
        let filter = CIFilter.areaAverage()
        filter.inputImage = input
        filter.extent = input.extent
        guard let output = filter.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        colorContext.render(output, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                            format: .RGBA8, colorSpace: nil)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
            .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // An average is muddy: more saturated and never dim, so the glow reads as the cover's hue.
        // A near-grey average (a white or a black cover) stays neutral instead of being pushed
        // into whatever hue its noise happens to lean.
        let saturation = s < 0.08 ? s : min(1, max(s * 1.5, 0.35))
        let lifted = UIColor(hue: h, saturation: saturation, brightness: max(b, 0.65), alpha: 1)
        colorCache.setObject(lifted, forKey: cacheKey)
        return Color(lifted)
    }

    @ViewBuilder private func face(height: CGFloat) -> some View {
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
