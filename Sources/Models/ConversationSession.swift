import Foundation
import AVFoundation
import Speech
import Translation

@Observable
@MainActor
final class ConversationSession {
    private(set) var messages: [Message] = []
    private(set) var isListeningA = false
    private(set) var isListeningB = false
    var errorMessage: String?

    var languageA: Locale = .init(identifier: "it_IT")
    var languageB: Locale = .init(identifier: "en_US")

    private let speechService = SpeechRecognitionService()
    private let ttsService = TextToSpeechService()

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let mic = await speechService.requestMicrophoneAuthorization()
        let speech = await speechService.requestSpeechAuthorization()
        return mic && speech
    }

    // MARK: - Conversation

    func startListening(userA: Bool) {
        guard !isListeningA && !isListeningB else { return }

        if userA {
            isListeningA = true
        } else {
            isListeningB = true
        }

        let source = userA ? languageA : languageB
        let target = userA ? languageB : languageA

        Task {
            do {
                let hasPermissions = await requestPermissions()
                guard hasPermissions else {
                    throw ConversationError.microphoneNotAuthorized
                }

                let text = try await speechService.startRecording(language: source)
                guard !text.isEmpty else {
                    if userA { isListeningA = false } else { isListeningB = false }
                    return
                }

                let availability = LanguageAvailability()
                let status = await availability.status(from: source.language, to: target.language)
                guard status == .installed || status == .supported else {
                    throw ConversationError.translationNotSupported
                }

                let translationSession = TranslationSession(
                    installedSource: source.language,
                    target: target.language
                )
                let response = try await translationSession.translate(text)

                let message = Message(
                    originalText: text,
                    translatedText: response.targetText,
                    sourceLanguage: source.languageCode ?? source.identifier,
                    targetLanguage: target.languageCode ?? target.identifier,
                    isUserA: userA,
                    timestamp: Date()
                )

                messages.append(message)
                ttsService.speak(text: response.targetText, language: target.identifier)
            } catch {
                if let convError = error as? ConversationError {
                    self.errorMessage = convError.localizedDescription
                } else {
                    self.errorMessage = error.localizedDescription
                }
            }

            if userA {
                isListeningA = false
            } else {
                isListeningB = false
            }
        }
    }

    func stopListening() {
        speechService.stopRecording()
    }

    func endConversation() {
        stopListening()
        messages.removeAll()
    }
}
