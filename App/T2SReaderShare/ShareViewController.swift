import SwiftUI
import T2SApp
import UIKit

/// UIKit entry point for the Share Extension. Its SwiftUI content only completes the request after
/// the shared-library import has finished, so a provider cannot disappear mid-import.
@MainActor
final class ShareViewController: UIViewController {
    private var service: ShareImportService?
    private var inputItems: [NSExtensionItem] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        inputItems = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        do {
            let shared = try SharedLibraryFactory.make()
            let service = ShareImportService(paths: shared.paths, model: shared.importModel)
            self.service = service
            embed(ShareImportView(service: service, itemCount: ShareImportService.attachmentCount(in: inputItems),
                                  add: { [weak self] in self?.addItems() },
                                  cancel: { [weak self] in self?.cancel() }))
        } catch {
            embed(ShareFailureView(message: "The shared library couldn't be opened. \(error.localizedDescription)",
                                   cancel: { [weak self] in self?.cancel() }))
        }
    }

    private func addItems() {
        guard let service else { return }
        Task { @MainActor [weak self, service] in
            let result = await service.importItems(self?.inputItems ?? [])
            guard case .success(let ids) = result, let first = ids.first, let self else { return }
            self.extensionContext?.open(LibraryHandoff.url(for: first)) { [weak self] _ in
                Task { @MainActor in self?.extensionContext?.completeRequest(returningItems: nil) }
            }
        }
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: ShareImportError.failed(["Import cancelled."]))
    }

    private func embed<Content: View>(_ root: Content) {
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }
}

/// The extension's own copy of the app's colours. `App/T2SReader/Design` is not in this target's
/// sources (App/project.yml), so the sheet cannot say `Tokens` — the system greys it already used
/// carry the light and dark, and the raised key's blue is copied here by value so the one control
/// that matters is the same object it is in the app. Inter is not registered in this process
/// either (the app target's `UIAppFonts` does not reach an extension), so the type is the system's.
private enum ShareTokens {
    static let ground = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let ink = Color(uiColor: .label)
    static let muted = Color(uiColor: .secondaryLabel)
    static let destructive = Color(uiColor: .systemRed)
    /// `Tokens.keyTop` / `keyBottom`: the key's face, royal blue at the top rim falling to indigo.
    static let keyTop = dynamic(light: 0x5477FF, dark: 0x5F81FF)
    static let keyBottom = dynamic(light: 0x2A1FE0, dark: 0x3226E8)
    /// `Tokens.glow`, and the pool of it the empty shelf lays under its picture.
    static let glow = dynamic(light: 0x0066FF, dark: 0x5F84FF)
    static let glowSoft = dynamic(light: 0x0066FF, dark: 0x5F84FF, lightAlpha: 0.18, darkAlpha: 0.24)
    static let glowFaint = dynamic(light: 0x0066FF, dark: 0x5F84FF, lightAlpha: 0.08, darkAlpha: 0.14)
    static let onKey = Color.white
    static let gloss = Color.white
    static let shade = Color.black
    static let ink2 = dynamic(light: 0x8A8A8A, dark: 0x8E8E8E)

    private static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let rgb = isDark ? dark : light
            return UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                           blue: CGFloat(rgb & 0xFF) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

/// The sheet the share extension puts up: a masthead with the way out at its right, the picture and
/// its one line in the middle of the page, and the raised blue key across the foot (owner,
/// 2026-09-16). It is laid out like the app's empty pages — a pool of the warm-up's blue with one
/// object standing in it, the words centred under it — so arriving from another app lands you on a
/// page that belongs to this one. Cancel is an icon rather than a second pill so nothing shares the
/// foot with the key: there is one thing to press, and it is the one that does the work.
private struct ShareImportView: View {
    @Bindable var service: ShareImportService
    let itemCount: Int
    let add: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ShareMasthead(cancel: cancel)
            Spacer(minLength: 24)
            VStack(spacing: 24) {
                ShareMark(status: service.status)
                VStack(spacing: 8) {
                    Text(statusText)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(ShareTokens.muted)
                        .contentTransition(.opacity)
                    if let error = service.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(ShareTokens.destructive)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 24)
            RaisedKey(label: "Add", busyLabel: service.status == .importing ? "Adding…" : nil, action: add)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShareTokens.ground)
        .animation(.snappy, value: service.status)
    }

    private var statusText: String {
        switch service.status {
        case .idle: return "\(itemCount) item\(itemCount == 1 ? "" : "s") ready to add"
        case .importing: return "Adding…"
        case .completed(let count): return "Added \(count) item\(count == 1 ? "" : "s")"
        }
    }
}

private struct ShareFailureView: View {
    let message: String
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ShareMasthead(cancel: cancel)
            Spacer(minLength: 24)
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(ShareTokens.destructive)
                    .frame(maxHeight: 180)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(ShareTokens.muted)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 24)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShareTokens.ground)
    }
}

/// The sheet's head: the title, big, with the way out at its right as a grey icon key.
private struct ShareMasthead: View {
    let cancel: () -> Void

    var body: some View {
        HStack {
            Text("Add to t2s")
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(ShareTokens.ink)
            Spacer(minLength: 12)
            Button(action: cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ShareTokens.muted)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(ShareTokens.surface))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")
        }
    }
}

/// The picture in the middle: the object standing in a pool of the warm-up's blue, as the app's
/// empty pages draw theirs. The object says where the sheet is — a page waiting, the spinner while
/// the library takes it, a tick once it is in.
private struct ShareMark: View {
    let status: ShareImportStatus

    var body: some View {
        ZStack {
            Pool()
            Group {
                if case .importing = status {
                    ProgressView()
                        .controlSize(.large)
                        .tint(ShareTokens.glow)
                } else {
                    Image(systemName: glyph)
                        .font(.system(size: 62, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: [ShareTokens.keyTop, ShareTokens.keyBottom],
                                                        startPoint: .top, endPoint: .bottom))
                        .shadow(color: ShareTokens.glow.opacity(0.35), radius: 18, y: 10)
                }
            }
            .transition(.opacity)
        }
        // A ceiling rather than a height: the pool is faded well before its own edge, so a short
        // sheet (a landscape host) squeezes the picture instead of pushing the key off the foot.
        .frame(maxHeight: 180)
        .accessibilityHidden(true)
    }

    private var glyph: String {
        if case .completed = status { return "checkmark.circle.fill" }
        return "doc.text.fill"
    }
}

/// `EmptyShelf`'s pool, at the size this page wants: a circle squashed flat and faded out well
/// before its own edge, so no frame of it shows.
private struct Pool: View {
    var body: some View {
        Circle()
            .fill(RadialGradient(stops: [
                .init(color: ShareTokens.glowSoft, location: 0),
                .init(color: ShareTokens.glowFaint, location: 0.45),
                .init(color: ShareTokens.glowFaint.opacity(0), location: 1),
            ], center: .center, startRadius: 0, endRadius: 130))
            .frame(width: 260, height: 260)
            .scaleEffect(x: 1, y: 0.68)
            .offset(y: 10)
    }
}

/// The app's `RaisedButton` in its `.blue` tone and `.bar` size, carried into this target: a capsule
/// lit from above, a bevel bright along the top rim and dark along the foot, a tight contact shadow
/// and a wide one in the face's own blue. A press sinks it. While the import runs it shows a
/// spinner in front of the word and cannot be pressed; disabled it is the flat grey slab the app
/// shows, because a raised key that does nothing would be a lie.
private struct RaisedKey: View {
    var label: String
    var busyLabel: String? = nil
    var action: () -> Void

    var body: some View {
        let busy = busyLabel != nil
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(ShareTokens.ink2) }
                Text(busyLabel ?? label).font(.headline)
            }
            .lineLimit(1)
            .foregroundStyle(busy ? ShareTokens.ink2 : ShareTokens.onKey)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .contentShape(Capsule())
        }
        .buttonStyle(RaisedStyle(raised: !busy))
        .disabled(busy)
        .animation(.snappy, value: busy)
    }
}

private struct RaisedStyle: ButtonStyle {
    /// False while the import runs: the flat slab, no bevel, no shadow.
    var raised: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && raised
        configuration.label
            .background {
                if raised {
                    Capsule()
                        .fill(LinearGradient(colors: [ShareTokens.keyTop, ShareTokens.keyBottom],
                                             startPoint: .top, endPoint: .bottom))
                        // Light from above: a gloss gone by the middle, shade gathering at the foot.
                        .overlay {
                            Capsule().fill(LinearGradient(stops: [
                                .init(color: ShareTokens.gloss.opacity(0.22), location: 0),
                                .init(color: ShareTokens.gloss.opacity(0.04), location: 0.42),
                                .init(color: ShareTokens.shade.opacity(0), location: 0.55),
                                .init(color: ShareTokens.shade.opacity(0.20), location: 1),
                            ], startPoint: .top, endPoint: .bottom))
                        }
                        .overlay {
                            Capsule().strokeBorder(LinearGradient(stops: [
                                .init(color: ShareTokens.gloss.opacity(0.75), location: 0),
                                .init(color: ShareTokens.gloss.opacity(0), location: 0.45),
                                .init(color: ShareTokens.shade.opacity(0), location: 0.55),
                                .init(color: ShareTokens.shade.opacity(0.38), location: 1),
                            ], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                        }
                        .overlay { Capsule().fill(ShareTokens.shade.opacity(pressed ? 0.18 : 0)) }
                } else {
                    Capsule().fill(ShareTokens.surface)
                }
            }
            .compositingGroup()                                                // one shadow for the key, not one per layer
            .shadow(color: ShareTokens.shade.opacity(!raised ? 0 : pressed ? 0.10 : 0.16), radius: pressed ? 1 : 2, y: pressed ? 0.5 : 1.5)
            .shadow(color: ShareTokens.glow.opacity(!raised ? 0 : pressed ? 0.22 : 0.40), radius: pressed ? 8 : 18, y: pressed ? 4 : 10)
            .scaleEffect(pressed ? 0.965 : 1)
            .animation(.snappy(duration: 0.18), value: pressed)
    }
}
