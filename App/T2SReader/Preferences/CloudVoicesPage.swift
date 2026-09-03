import SwiftUI
import T2SApp
import T2SAudio

/// Preferences → Cloud voices. This page owns no provider integration beyond the deliberately
/// small PCM JSON contract; credentials stay in `KeychainSecretStore` and are never read into the
/// UI after saving.
struct CloudVoicesPage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var apiKey = ""
    @State private var keyIsStored = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var isWorking = false
    @State private var pendingRouteID: String?

    var body: some View {
        @Bindable var settings = env.cloudVoiceSettings
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                PageTitle(text: "Cloud voices", subtitle: "Use your own provider and API key.")
                section("Provider contract") {
                    Text("This is a generic OpenAI-compatible PCM endpoint. It receives model, input, voice, pcm_f32le at 24 kHz, and optional word timestamps.")
                        .typeRole(.meta)
                        .foregroundStyle(Tokens.ink2)
                    Text("Requests and charges go directly to your provider.")
                        .typeRole(.meta)
                        .foregroundStyle(Tokens.ink2)
                }
                section("Configuration") {
                    field("HTTPS endpoint", text: $settings.endpointText, contentType: .URL)
                    field("Model", text: $settings.model)
                    field("Provider voice", text: $settings.voice)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Request rate").typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                            Text("Maximum requests per minute").typeRole(.meta).foregroundStyle(Tokens.ink2)
                        }
                        Spacer()
                        Stepper("\(settings.requestRatePerMinute) / min", value: $settings.requestRatePerMinute, in: 1...120)
                            .labelsHidden()
                            .accessibilityLabel("Request rate")
                        Text("\(settings.requestRatePerMinute) / min").typeRole(.mono).foregroundStyle(Tokens.ink2)
                    }
                    SecureField("API key", text: $apiKey)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Tokens.surface, in: Capsule())
                    Text(keyIsStored ? "An API key is stored securely on this device." : "No API key is stored.")
                        .typeRole(.meta)
                        .foregroundStyle(Tokens.ink2)
                    HStack(spacing: 8) {
                        Pill(label: isWorking ? "Saving…" : "Save", style: .accent) { beginSave() }
                            .disabled(isWorking)
                        Pill(label: "Remove key", style: .destructiveSoft) { removeKey() }
                            .disabled(isWorking || !keyIsStored)
                        Pill(label: "Test voice", glyph: "waveform", style: .soft) { testVoice() }
                            .disabled(isWorking || env.cloudVoiceSettings.activeVoiceID == nil || !keyIsStored)
                    }
                }
                section("Status") {
                    Text(routeStatus).typeRole(.meta).foregroundStyle(Tokens.ink2)
                    if let result {
                        Text(result)
                            .typeRole(.meta)
                            .foregroundStyle(resultIsError ? Tokens.destructive : Tokens.positive)
                    }
                }
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .background(Tokens.ground)
        .task { refreshKeyStatus() }
        .alert("Rendered audio will be replaced", isPresented: routeChangeAlert) {
            Button("Keep current", role: .cancel) { pendingRouteID = nil }
            Button("Change voice", role: .destructive) {
                guard let routeID = pendingRouteID else { return }
                pendingRouteID = nil
                save(routeID: routeID)
            }
        } message: {
            Text("Changing this cloud voice discards \(DurationFormatter.long(discardedSeconds)) of rendered audio for the current document. It will render again with the new voice.")
        }
    }

    private var routeChangeAlert: Binding<Bool> {
        Binding(get: { pendingRouteID != nil }, set: { if !$0 { pendingRouteID = nil } })
    }

    private var discardedSeconds: TimeInterval {
        guard let current = env.player.current else { return 0 }
        return env.voiceChange.discardedSeconds(for: current)
    }

    private var routeStatus: String {
        guard let route = env.cloudVoiceSettings.activeVoiceID else {
            return "No active cloud route. Save a valid HTTPS endpoint, model, and voice to enable one."
        }
        return keyIsStored ? "Cloud route active: \(route.prefix(24))…" : "Cloud route is configured; add an API key to use it."
    }

    private func field(_ title: String, text: Binding<String>, contentType: UITextContentType? = nil) -> some View {
        TextField(title, text: text)
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Tokens.surface, in: Capsule())
    }

    private func beginSave() {
        do {
            try env.cloudVoiceSettings.validate()
            guard let routeID = env.cloudVoiceSettings.cloudVoiceID else { return }
            if shouldConfirmRouteChange(to: routeID) {
                pendingRouteID = routeID
            } else {
                save(routeID: routeID)
            }
        } catch {
            setError(error)
        }
    }

    private func shouldConfirmRouteChange(to routeID: String) -> Bool {
        guard env.cloudVoiceSettings.activeVoiceID != nil,
              env.cloudVoiceSettings.activeVoiceID != routeID,
              discardedSeconds > 0,
              let current = env.player.current
        else { return false }
        return current.document.voiceID?.hasPrefix("cloud:") == true
            || (current.document.voiceID == nil && env.preferences.defaultVoiceID?.hasPrefix("cloud:") == true)
    }

    private func save(routeID: String) {
        isWorking = true
        Task {
            do {
                try await env.cloudVoiceSettings.save()
                if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try env.cloudVoiceSecrets.save(apiKey)
                    apiKey = ""
                }
                refreshKeyStatus()
                applyRouteChange(routeID)
                result = "Cloud voice settings saved."
                resultIsError = false
            } catch {
                setError(error)
            }
            isWorking = false
        }
    }

    private func applyRouteChange(_ routeID: String) {
        let wasCloudDefault = env.preferences.defaultVoiceID?.hasPrefix("cloud:") == true
        let defaultChanged = env.preferences.defaultVoiceID != routeID
        if wasCloudDefault { env.preferences.defaultVoiceID = routeID }
        guard let current = env.player.current else { return }
        if current.document.voiceID?.hasPrefix("cloud:") == true, current.document.voiceID != routeID {
            Task { _ = await env.voiceChange.apply(voiceID: routeID, to: current) }
        } else if current.document.voiceID == nil, wasCloudDefault, defaultChanged {
            Task { await env.player.load(current, play: false) }
        }
    }

    private func removeKey() {
        do {
            try env.cloudVoiceSecrets.save("")
            apiKey = ""
            keyIsStored = false
            result = "The API key was removed from this device."
            resultIsError = false
        } catch {
            setError(error)
        }
    }

    private func testVoice() {
        guard let routeID = env.cloudVoiceSettings.activeVoiceID else {
            setError(HTTPVoiceError.notConfigured)
            return
        }
        isWorking = true
        Task {
            do {
                _ = try await env.cloudRouter.synthesize(.init(spoken: "This is a short voice test.", voiceID: routeID))
                result = "Voice test succeeded."
                resultIsError = false
            } catch {
                setError(error)
            }
            isWorking = false
        }
    }

    private func refreshKeyStatus() {
        do {
            keyIsStored = try !(env.cloudVoiceSecrets.load()?.isEmpty ?? true)
        } catch {
            setError(error)
        }
    }

    private func setError(_ error: Error) {
        result = error.localizedDescription
        resultIsError = true
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).typeRole(.sectionHeader).foregroundStyle(Tokens.ink)
            content()
        }
    }
}
