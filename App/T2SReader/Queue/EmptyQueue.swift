// App/T2SReader/Queue/EmptyQueue.swift
import SwiftUI

/// Spec §2.4.5 empty state: a grey paragraph explaining the share sheet and an "Import" pill.
struct EmptyQueue: View {
    var onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nothing queued yet. Share an article or a book from any app to t2s, or import one here. Everything you add plays right away — no waiting for it to process.")
                .typeRole(.meta)
                .foregroundStyle(Tokens.ink2)
            Pill(label: "Import", glyph: "plus", style: .soft, action: onImport)
        }
        .padding(.top, Spacing.grid)
    }
}
