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

    private static func image(at path: String) -> UIImage? {
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

/// The `positive` check that means "ready": plays with no synthesis and no network (spec §3.4.1).
struct PositiveCheck: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 16))
            .foregroundStyle(Tokens.positive)
            .accessibilityLabel("Ready to play offline")
    }
}
