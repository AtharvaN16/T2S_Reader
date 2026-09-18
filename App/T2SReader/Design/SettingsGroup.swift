// App/T2SReader/Design/SettingsGroup.swift
import SwiftUI

/// The grouped list Settings' subpages are made of (owner, 2026-09-14, picking it out of the
/// Storage directions): rows on one `surface` slab, a hairline between them and none after the
/// last, so a group reads as one object rather than as a stack of separate rows.
///
/// `surface`, which means a `.soft` `Pill` — also `surface` — would vanish inside one. That is on
/// purpose: a row in a group carries a *word* or a glyph at its end, in ink or in red, the way the
/// chapter rows do. A group is not a place for chips.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 16)
            .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// One row of a `SettingsGroup`: a title, an optional second line under it, a value at the far end,
/// and whatever the row's own action wears after that.
///
/// `separator` is the caller's to set — true on every row but the first — because the divider
/// belongs *between* rows, and a row cannot see its neighbours from inside a `ViewBuilder`.
struct SettingsGroupRow<Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    /// The number at the end of the row, in ink and tabular, so a column of sizes lines up.
    var value: String? = nil
    var separator: Bool = false
    /// Dimmed title and value, for a row that is listed rather than offered — a book with nothing
    /// picked in it.
    var isQuiet: Bool = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            if separator {
                Rectangle().fill(Tokens.ink3).frame(height: 1).opacity(0.7)
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .typeRole(.settingsRow)
                        .foregroundStyle(isQuiet ? Tokens.ink2 : Tokens.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let subtitle {
                        Text(subtitle).typeRole(.meta).foregroundStyle(Tokens.ink2).lineLimit(1)
                    }
                }
                // The title is the one flexible child; everything after it holds its width, which
                // is what keeps a long book title from pushing a control off the page's margin.
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .typeRole(.meta)
                        .foregroundStyle(isQuiet ? Tokens.ink2 : Tokens.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                trailing
            }
            .frame(minHeight: 48)
        }
    }
}

extension SettingsGroupRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, value: String? = nil,
         separator: Bool = false, isQuiet: Bool = false) {
        self.init(title: title, subtitle: subtitle, value: value,
                  separator: separator, isQuiet: isQuiet) { EmptyView() }
    }
}

/// The chevron a row wears when it opens something — `ink3`, as Settings' own rows draw it.
struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Tokens.ink3)
    }
}

/// A word at the end of a row that does something, rather than a pill: inside a `surface` group a
/// soft pill is invisible, and a destructive act reads louder as red lettering than as a red slab
/// repeated down a list (the Book sheet's lesson, 2026-09-14).
struct RowAction: View {
    var label: String
    var isDestructive: Bool = false
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .typeRole(.pill)
                .foregroundStyle(isEnabled ? (isDestructive ? Tokens.destructive : Tokens.ink) : Tokens.ink3)
                // A target the size of the trash beside it, without the word moving.
                .padding(.vertical, 10)
                .padding(.leading, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - Rows with a tile

/// The small coloured square at the head of a Settings row (owner, 2026-09-18, from a reference
/// whose every row leads with one): a glyph in white on a `continuous` rounded square, 30 pt, so
/// eight of them down a page read as a column of marks rather than as eight icons.
struct IconTile: View {
    var systemName: String
    var color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Tokens.onTile)
            .frame(width: 30, height: 30)
            .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A row of Settings' root: tile, title, an optional grey value under it, and at the end
/// whatever the row does — a `RowChevron` when it opens a page or sheet, a `RowArrow` when it
/// acts at once, a `Toggle` when it is a switch. The chevron used to mean all three (2026-09-18).
///
/// The hairline over a row starts where the words start, not at the tile, as the reference draws
/// it: a line that runs under the tiles cuts the column of marks into pieces.
struct SettingsRow<Trailing: View>: View {
    var icon: String
    var color: Color
    var title: String
    var subtitle: String? = nil
    var separator: Bool = false
    @ViewBuilder var trailing: Trailing

    private static var tileWidth: CGFloat { 30 + 14 }

    var body: some View {
        VStack(spacing: 0) {
            if separator {
                Rectangle().fill(Tokens.ink3).frame(height: 1).opacity(0.7)
                    .padding(.leading, Self.tileWidth)
            }
            HStack(alignment: .center, spacing: 14) {
                IconTile(systemName: icon, color: color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .typeRole(.settingsRow)
                        .foregroundStyle(Tokens.ink)
                        .lineLimit(1)
                    // Two lines, not one: a value fits in one, but the sync row's line is a
                    // status sentence, and a status cut to "Needs an iCloud-enabled b…" says nothing.
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).typeRole(.meta).foregroundStyle(Tokens.ink2).lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                trailing
            }
            .frame(minHeight: 54)
        }
        .contentShape(Rectangle())
    }
}

extension SettingsRow where Trailing == RowChevron {
    /// A row that opens something.
    init(icon: String, color: Color, title: String, subtitle: String? = nil, separator: Bool = false) {
        self.init(icon: icon, color: color, title: title, subtitle: subtitle, separator: separator) { RowChevron() }
    }
}

/// The mark on a row that does something the moment it is tapped rather than opening a page —
/// the reference's "Rate in App Store" arrow. Distinct from the chevron so the chevron can keep
/// one meaning.
struct RowArrow: View {
    var body: some View {
        Image(systemName: "arrow.up.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Tokens.ink3)
    }
}
