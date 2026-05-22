import Foundation
import AVFoundation
import Speech
import Translation
import os.log

enum ConversationPhase: String {
    case idle = "✅ Pronto"
    case listening = "🎤 In ascolto..."
    case transcribed = "📝 Trascrizione completata"
    case translating = "🌐 Traduzione in corso..."
    case speaking = "🔊 Lettura in corso..."
    case error = "⚠️ Errore"
}

struct PhaseLogEntry: Identifiable {
    let id = UUID()
    let text: String
}

@Observable
@MainActor
final class ConversationSession {
    private(set) var messages: [Message] = []
    private(set) var isListeningA = false
    private(set) var isListeningB = false
    private(set) var errorMessage: String?
    private(set) var phase: ConversationPhase = .idle
    private(set) var phaseHistory: [PhaseLogEntry] = []

    var languageA: Locale = .init(identifier: "it_IT")
    var languageB: Locale = .init(identifier: "en_US")

    // SwiftUI translation task configuration
    private(set) var translationConfig: TranslationSession.Configuration?
    private(set) var pendingTranslationText: String?
    private var pendingUserA: Bool?

    private let speechService = SpeechRecognitionService()
    private let ttsService = TextToSpeechService()
    private var idleTask: Task<Void, Never>?

    private func setPhase(_ newPhase: ConversationPhase) {
        phase = newPhase
        let entry = PhaseLogEntry(
            text: "\(Date().formatted(date: .omitted, time: .standard)) — \(newPhase.rawValue)"
        )
        phaseHistory.append(entry)
        if phaseHistory.count > 30 {
            phaseHistory.removeFirst(phaseHistory.count - 30)
        }
        os_log("[reaLang] Phase changed to: %{public}@", log: .default, type: .info, newPhase.rawValue)
    }

    private func cancelIdleTask() {
        idleTask?.cancel()
        idleTask = nil
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let mic = await speechService.requestMicrophoneAuthorization()
        let speech = await speechService.requestSpeechAuthorization()
        return mic && speech
    }

    // MARK: - Conversation

    func startListening(userA: Bool) async {
        os_log("[reaLang] startListening called, userA: %{public}d, isListeningA: %{public}d, isListeningB: %{public}d", log: .default, type: .info, userA, isListeningA, isListeningB)
        cancelIdleTask()
        guard !isListeningA && !isListeningB else {
            os_log("[reaLang] BLOCKED: already listening", log: .default, type: .info)
            return
        }

        if userA {
            isListeningA = true
        } else {
            isListeningB = true
        }
        setPhase(.listening)
        os_log("[reaLang] isListening set: A=%{public}d, B=%{public}d", log: .default, type: .info, isListeningA, isListeningB)

        let source = userA ? languageA : languageB
        let target = userA ? languageB : languageA

        defer {
            if userA {
                isListeningA = false
            } else {
                isListeningB = false
            }
            os_log("[reaLang] DEFER reset isListening: A=%{public}d, B=%{public}d", log: .default, type: .info, isListeningA, isListeningB)
        }

        do {
            os_log("[reaLang] Requesting permissions...", log: .default, type: .info)
            let hasPermissions = await requestPermissions()
            os_log("[reaLang] Permissions result: %{public}d", log: .default, type: .info, hasPermissions)
            guard hasPermissions else {
                throw ConversationError.microphoneNotAuthorized
            }

            os_log("[reaLang] Starting speech recording for %{public}@", log: .default, type: .info, source.identifier)
            let text = try await speechService.startRecording(language: source)
            os_log("[reaLang] Recording returned text: '%{public}@'", log: .default, type: .info, text)
            guard !text.isEmpty else {
                os_log("[reaLang] Empty text, aborting", log: .default, type: .info)
                setPhase(.idle)
                return
            }

            setPhase(.transcribed)

            let availability = LanguageAvailability()
            let status = await availability.status(from: source.language, to: target.language)
            os_log("[reaLang] Translation availability: %{public}@ from %{public}@ to %{public}@", log: .default, type: .info, String(describing: status), source.identifier, target.identifier)
            guard status != .unsupported else {
                throw ConversationError.translationNotSupported
            }

            os_log("[reaLang] Setting up translation task", log: .default, type: .info)
            setPhase(.translating)
            pendingTranslationText = text
            pendingUserA = userA
            translationConfig = TranslationSession.Configuration(
                source: source.language,
                target: target.language
            )
        } catch {
            os_log("[reaLang] ERROR in startListening: %{public}@", log: .default, type: .info, error.localizedDescription)
            setPhase(.error)
            if let convError = error as? ConversationError {
                self.errorMessage = convError.localizedDescription
            } else {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func stopListening() {
        os_log("[reaLang] stopListening called, resetting UI state immediately", log: .default, type: .info)
        isListeningA = false
        isListeningB = false
        speechService.stopRecording()
    }

    func finalizeTranslation(response: TranslationSession.Response) {
        guard let text = pendingTranslationText,
              let userA = pendingUserA else { return }

        let source = userA ? languageA : languageB
        let target = userA ? languageB : languageA

        let message = Message(
            originalText: text,
            translatedText: response.targetText,
            sourceLanguage: source.language.languageCode?.identifier ?? source.identifier,
            targetLanguage: target.language.languageCode?.identifier ?? target.identifier,
            isUserA: userA,
            timestamp: Date()
        )

        messages.append(message)
        setPhase(.speaking)
        ttsService.speak(text: response.targetText, language: target.identifier)
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            self.setPhase(.idle)
        }

        // Reset pending state
        pendingTranslationText = nil
        pendingUserA = nil
        translationConfig = nil
    }

    func clearError() {
        cancelIdleTask()
        errorMessage = nil
        setPhase(.idle)
    }

    func handleTranslationError(_ error: Error) {
        cancelIdleTask()
        setPhase(.error)
        if let convError = error as? ConversationError {
            self.errorMessage = convError.localizedDescription
        } else {
            self.errorMessage = error.localizedDescription
        }
        translationConfig = nil
        pendingTranslationText = nil
    }

    func endConversation() {
        stopListening()
        cancelIdleTask()
        setPhase(.idle)
        messages.removeAll()
        translationConfig = nil
        pendingTranslationText = nil
        pendingUserA = nil
    }
}
