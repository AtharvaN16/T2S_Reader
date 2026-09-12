import Foundation
import Observation
import T2SAudio

/// The app-side abstraction for the sole secret in the cloud-voice feature. Implementations must
/// use Keychain Services; settings deliberately retain only non-secret provider configuration.
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
/// configuration without reaching into a MainActor preferences model.
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

/// Non-secret BYO provider settings. The API key is intentionally absent from this type and from
/// its `UserDefaults` suite; `save()` validates before making a route active.
@MainActor
@Observable
public final class CloudVoiceSettings {
    public static let defaultRateLimit = 60

    private enum Key {
        static let endpoint = "cloudVoice.endpoint"
        static let model = "cloudVoice.model"
        static let voice = "cloudVoice.voice"
        static let rate = "cloudVoice.requestRatePerMinute"
        /// The endpoint text the app itself last wrote, so a later build can tell its own route
        /// from the reader's edit.
        static let shippedEndpoint = "cloudVoice.shippedEndpoint"
    }

    private let defaults: UserDefaults
    public let configurationStore: CloudVoiceConfigurationStore

    public var endpointText: String {
        didSet { defaults.set(endpointText, forKey: Key.endpoint) }
    }

    public var model: String {
        didSet { defaults.set(model, forKey: Key.model) }
    }

    public var voice: String {
        didSet { defaults.set(voice, forKey: Key.voice) }
    }

    public var requestRatePerMinute: Int {
        didSet {
            let clamped = min(120, max(1, requestRatePerMinute))
            if requestRatePerMinute != clamped {
                requestRatePerMinute = clamped
            } else {
                defaults.set(requestRatePerMinute, forKey: Key.rate)
            }
        }
    }

    public init(defaults: UserDefaults = .standard, shipped: CloudVoiceDefaults? = nil) {
        self.defaults = defaults
        if let shipped {
            let stored = defaults.string(forKey: Key.endpoint)
            let written = defaults.string(forKey: Key.shippedEndpoint)
            // First launch, or a route still exactly as the app itself wrote it — by the marker, or
            // by value for a build that kept none — takes the current shipped route. An edit, even
            // to nothing, is the reader's and is never overwritten.
            let untouched = stored == nil || stored == written || CloudVoiceDefaults.superseded.contains(stored ?? "")
            if untouched, stored != shipped.endpointText {
                defaults.set(shipped.endpointText, forKey: Key.endpoint)
                defaults.set(shipped.model, forKey: Key.model)
                defaults.set(shipped.voice, forKey: Key.voice)
                defaults.set(shipped.requestRatePerMinute, forKey: Key.rate)
            }
            if untouched { defaults.set(shipped.endpointText, forKey: Key.shippedEndpoint) }
        }
        let savedEndpoint = defaults.string(forKey: Key.endpoint) ?? ""
        let savedModel = defaults.string(forKey: Key.model) ?? ""
        let savedVoice = defaults.string(forKey: Key.voice) ?? ""
        let storedRate = defaults.object(forKey: Key.rate) as? Int ?? Self.defaultRateLimit
        let savedRate = min(120, max(1, storedRate))
        endpointText = savedEndpoint
        model = savedModel
        voice = savedVoice
        requestRatePerMinute = savedRate
        configurationStore = CloudVoiceConfigurationStore(configuration: try? Self.makeConfiguration(
            endpointText: savedEndpoint,
            model: savedModel,
            voice: savedVoice,
            rate: savedRate
        ))
    }

    /// This route ID has no API key and changes with every rendering-affecting cloud setting.
    public var cloudVoiceID: String? {
        guard let configuration = try? Self.makeConfiguration(endpointText: endpointText, model: model,
                                                               voice: voice, rate: requestRatePerMinute)
        else { return nil }
        return CloudVoiceID(configuration: configuration, voice: configuration.voice).rawValue
    }

    public var activeVoiceID: String? {
        guard let configuration = configurationStore.current() else { return nil }
        return CloudVoiceID(configuration: configuration, voice: configuration.voice).rawValue
    }

    public func validate() throws {
        _ = try Self.makeConfiguration(endpointText: endpointText, model: model, voice: voice,
                                       rate: requestRatePerMinute)
    }

    public func save() async throws {
        let configuration = try Self.makeConfiguration(endpointText: endpointText, model: model, voice: voice,
                                                        rate: requestRatePerMinute)
        configurationStore.replace(with: configuration)
    }

    public func removeRoute() {
        configurationStore.replace(with: nil)
    }

    /// One endpoint per line, the first being the primary; blank lines are ignored. A single line
    /// is what every existing install has stored, and it parses as before.
    private static func makeConfiguration(endpointText: String, model: String, voice: String, rate: Int) throws -> HTTPVoiceConfiguration {
        let endpoints = try endpointText.split(whereSeparator: \.isNewline).compactMap { line -> URL? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            guard let url = URL(string: trimmed) else { throw HTTPVoiceError.invalidConfiguration }
            return url
        }
        guard !endpoints.isEmpty else { throw HTTPVoiceError.invalidConfiguration }
        let configuration = HTTPVoiceConfiguration(endpoints: endpoints, model: model, voice: voice, requestRatePerMinute: rate)
        try configuration.validate()
        return configuration
    }
}
