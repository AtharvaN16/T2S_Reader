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

private enum ShareTokens {
    static let ground = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let ink = Color(uiColor: .label)
    static let muted = Color(uiColor: .secondaryLabel)
    static let accent = Color.accentColor
    static let destructive = Color(uiColor: .systemRed)
}

private struct ShareImportView: View {
    @Bindable var service: ShareImportService
    let itemCount: Int
    let add: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add to t2s")
                .font(.title2.weight(.bold))
                .foregroundStyle(ShareTokens.ink)
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(ShareTokens.muted)
            if let error = service.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(ShareTokens.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
            HStack(spacing: 12) {
                Button("Cancel", action: cancel)
                    .buttonStyle(.bordered)
                    .tint(ShareTokens.ink)
                Button("Add", action: add)
                    .buttonStyle(.borderedProminent)
                    .tint(ShareTokens.accent)
                    .disabled(service.status == .importing)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(24)
        .background(ShareTokens.ground)
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
        VStack(alignment: .leading, spacing: 20) {
            Text("Add to t2s").font(.title2.weight(.bold)).foregroundStyle(ShareTokens.ink)
            Text(message).font(.footnote).foregroundStyle(ShareTokens.destructive)
            Spacer()
            Button("Cancel", action: cancel)
                .buttonStyle(.bordered)
                .tint(ShareTokens.ink)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(24)
        .background(ShareTokens.ground)
    }
}
