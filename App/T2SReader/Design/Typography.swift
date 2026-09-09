// App/T2SReader/Design/Typography.swift
import SwiftUI

/// Spec §2.4.1 type roles: Inter with tight tracking on display and label text, normal tracking on
/// meta, monospaced digits for anything that counts. Sizes are Dynamic Type relative.
enum TypeRole {
    case pageTitle, playerTitle, cardTitle, groupTitle, sectionHeader, rowTitle, pill, meta, mono

    var font: Font {
        switch self {
        case .pageTitle: return .custom("InterDisplay-Black", size: 34, relativeTo: .largeTitle)
        case .playerTitle: return .custom("InterDisplay-ExtraBold", size: 26, relativeTo: .title)
        case .cardTitle: return .custom("Inter-SemiBold", size: 19, relativeTo: .title3)
        /// Settings' section headings: bigger and heavier than `sectionHeader`.
        case .groupTitle: return .custom("Inter-Bold", size: 22, relativeTo: .title2)
        case .sectionHeader: return .custom("Inter-SemiBold", size: 17, relativeTo: .headline)
        case .rowTitle: return .custom("Inter-Medium", size: 17, relativeTo: .body)
        case .pill: return .custom("Inter-Medium", size: 15, relativeTo: .subheadline)
        case .meta: return .custom("Inter-Regular", size: 13, relativeTo: .footnote)
        case .mono: return .system(.footnote, design: .monospaced)
        }
    }

    /// Tracking in points at the role's base size (em × size).
    var tracking: CGFloat {
        switch self {
        case .pageTitle: return -0.03 * 34
        case .playerTitle: return -0.025 * 26
        case .cardTitle: return -0.02 * 19
        case .groupTitle: return -0.02 * 22
        case .sectionHeader, .rowTitle: return -0.01 * 17
        case .pill: return -0.01 * 15
        case .meta, .mono: return 0
        }
    }

    var lineLimit: Int? {
        switch self {
        case .playerTitle: return 4
        case .cardTitle, .rowTitle: return 2
        default: return nil
        }
    }
}

extension View {
    /// The role's line limit is a default, not an override: environment modifiers nearest the text
    /// win, so a plain `.lineLimit(role.lineLimit)` here would silently beat any `.lineLimit(n)` a
    /// caller adds after `typeRole`. Setting it only when nothing else has lets either order work.
    func typeRole(_ role: TypeRole) -> some View {
        font(role.font).tracking(role.tracking)
            .transformEnvironment(\.lineLimit) { limit in if limit == nil { limit = role.lineLimit } }
    }
}
