import Foundation
import T2SAudio

/// The app-side abstraction for the sole secret in the cloud-voice feature. Implementations must
/// use Keychain Services; nothing else the route needs is secret.
public protocol SecretStoring: Sendable {
    func save(_ value: String) throws
    func load() throws -> String?
}

/// Test/UI-preview store. Production wires `KeychainSecretStore` from the app target instead.
public final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    public init(value: String? = nil) { self.value = value }

    public func save(_ value: String) throws {
        lock.lock()
        self.value = value.isEmpty ? nil : value
        lock.unlock()
    }

    public func load() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// A lock-protected route snapshot lets the serial renderer read the active non-secret
/// configuration without reaching into a MainActor model.
public final class CloudVoiceConfigurationStore: @unchecked Sendable {
    private let lock = NSLock()
    private var configuration: HTTPVoiceConfiguration?

    public init(configuration: HTTPVoiceConfiguration? = nil) {
        self.configuration = configuration
    }

    public func current() -> HTTPVoiceConfiguration? {
        lock.lock()
        defer { lock.unlock() }
        return configuration
    }

    public func replace(with configuration: HTTPVoiceConfiguration?) {
        lock.lock()
        self.configuration = configuration
        lock.unlock()
    }
}
