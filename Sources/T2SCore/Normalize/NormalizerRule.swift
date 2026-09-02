public protocol NormalizerRule: Sendable {
    func apply(_ input: NormalizedText) -> NormalizedText
}
