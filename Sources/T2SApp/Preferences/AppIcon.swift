// Sources/T2SApp/Preferences/AppIcon.swift
import Foundation

/// The app icon in its ten liveries (2026-09-19): the wizard reading by the light of his book, as
/// drawn in the Figma file ("App icons", node 97:36), chosen on Settings → Appearance.
///
/// iOS keeps the choice, not the app: `UIApplication.alternateIconName` is the one true answer, and
/// a preference beside it would be a second answer free to disagree with the first. So this is
/// only the list — which icons there are, what each is called, and which assets it is — and
/// `init(alternateIconName:)` is the way back from what the system says to a cell of the grid.
///
/// Two assets per icon. The `.appiconset` is what the build compiles and iOS installs, and it
/// cannot be loaded by name at run time; the grid draws a plain `.imageset` of the same picture
/// instead (`previewAssetName`). `AppIconTests` holds this list, the build setting that names the
/// alternates and the asset catalog to one another, so none of the three can drift alone.
public enum AppIcon: String, CaseIterable, Identifiable, Sendable {
    case standard, dark, stealth, rainbow, halloween, amber, candy, zen, metal, pixel

    public var id: String { rawValue }

    /// The word under the cell, and the suffix of both asset names.
    public var title: String {
        switch self {
        case .standard: return "Default"
        case .dark: return "Dark"
        case .stealth: return "Stealth"
        case .rainbow: return "Rainbow"
        case .halloween: return "Halloween"
        case .amber: return "Amber"
        case .candy: return "Candy"
        case .zen: return "Zen"
        case .metal: return "Metal"
        case .pixel: return "Pixel"
        }
    }

    /// The name the build gives the icon set and the name handed to `setAlternateIconName`. Nil
    /// for the default: it is the primary icon, and the primary has no alternate name.
    public var alternateIconName: String? {
        self == .standard ? nil : "AppIcon-\(title)"
    }

    /// The preview `imageset` in the catalog's `AppIconPreviews` folder.
    public var previewAssetName: String { "IconPreview-\(title)" }

    /// The choice iOS reports. A name it no longer knows — an icon dropped from a later build —
    /// is the default rather than a blank grid.
    public init(alternateIconName: String?) {
        self = Self.allCases.first { $0.alternateIconName == alternateIconName } ?? .standard
    }
}
