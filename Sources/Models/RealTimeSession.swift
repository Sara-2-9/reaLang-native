import Foundation
import AVFoundation
import Speech
import Translation
import os.log

enum RealTimePhase: String {
    case idle = "✅ Pronto"
    case listening = "🎤 Ascolto in corso..."
    case translating = "🌐 Traduzione in corso..."
    case speaking = "🔊 Riproduzione in corso..."
    case error = "⚠️ Errore"
    case waitingHeadset = "🎧 Collega le cuffie"
}

private final class TranslationSessionBox: @unchecked Sendable {
    let session: TranslationSession
    init(session: TranslationSession) {
        self.session = session
    }
}

@Observable
@MainActor
final class RealTimeSession {
    private(set) var isRunning = false
    private(set) var liveTranscription = ""
    private(set) var liveTranslation = ""
    private(set) var phase: RealTimePhase = .idle
    private(set) var errorMessage: String?
    private(set) var isSpeaking = false

    var sourceLanguage: Locale
    var targetLanguage: Locale

    private let speechService = StreamingSpeechService()
    private let ttsService = StreamingTTSService()
    let audioRouteService = AudioRouteService()

    private var stabilizationTask: Task<Void, Never>?

    private var translationStreamContinuation: AsyncStream<String>.Continuation?
    private var translationConsumerTask: Task<Void, Never>?
    private var lastProcessedLength = 0
    private var lastTranscriptionUpdate = Date.distantPast
    private var isTranslating = false

    private let maxTranslationLength = 5000

    init(sourceLanguage: Locale, targetLanguage: Locale) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage

        ttsService.onSpeakingChanged = { [weak self] speaking in
            Task { @MainActor in
                self?.isSpeaking = speaking
                self?.updatePhase()
            }
        }

        audioRouteService.onHeadsetStatusChanged = { [weak self] connected in
            Task { @MainActor in
                if !connected && self?.isRunning == true {
                    self?.errorMessage = "Cuffie scollegate. La sessione è stata interrotta."
                    self?.stop()
                }
            }
        }
    }

    // MARK: - Public

    func start() async {
        guard !isRunning else { return }
        guard audioRouteService.isHeadsetConnected else {
            errorMessage = "Collega delle cuffie per usare la traduzione real-time."
            phase = .waitingHeadset
            return
        }

        isRunning = true
        liveTranscription = ""
        liveTranslation = ""
        lastProcessedLength = 0
        errorMessage = nil
        updatePhase()

        do {
            let availability = LanguageAvailability()
            let status = await availability.status(from: sourceLanguage.language, to: targetLanguage.language)
            guard status != .unsupported else {
                isRunning = false
                errorMessage = ConversationError.translationNotSupported.localizedDescription
                phase = .error
                return
            }

            let session = try await TranslationSession(
                installedSource: sourceLanguage.language,
                target: targetLanguage.language
            )
            let box = TranslationSessionBox(session: session)

            let stream = AsyncStream<String> { continuation in
                self.translationStreamContinuation = continuation
            }
            translationConsumerTask = Task { [weak self, box] in
                guard let self else { return }
                for await text in stream {
                    guard !Task.isCancelled else { break }
                    await self.performTranslation(of: text, box: box)
                }
            }

            speechService.onResult = { [weak self] text, isFinal in
                Task { @MainActor in
                    self?.handleTranscription(text, isFinal: isFinal)
                }
            }
            speechService.onError = { [weak self] error in
                Task { @MainActor in
                    self?.handleError(error)
                }
            }

            try await speechService.startContinuousRecognition(language: sourceLanguage)
        } catch {
            isRunning = false
            handleError(error)
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        speechService.stopContinuousRecognition()
        ttsService.stop()
        stabilizationTask?.cancel()
        stabilizationTask = nil
        translationStreamContinuation?.finish()
        translationStreamContinuation = nil
        translationConsumerTask?.cancel()
        translationConsumerTask = nil
        phase = .idle
    }

    func clearError() {
        errorMessage = nil
        updatePhase()
    }

    // MARK: - Transcription Handling

    private func handleTranscription(_ text: String, isFinal: Bool) {
        liveTranscription = text
        lastTranscriptionUpdate = Date()
        updatePhase()

        let lowerBound = text.index(text.startIndex, offsetBy: min(lastProcessedLength, text.count))
        let newText = String(text[lowerBound...])

        // Estrai frasi complete per punteggiatura
        if let endIndex = newText.lastIndex(where: { ".!?;:\n".contains($0) }) {
            let sentence = String(newText[...endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                enqueueTranslation(sentence)
            }
            let absoluteEnd = text.index(lowerBound, offsetBy: newText.distance(from: newText.startIndex, to: endIndex) + 1)
            lastProcessedLength = text.distance(from: text.startIndex, to: absoluteEnd)
        } else if isFinal && !newText.isEmpty {
            let sentence = newText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                enqueueTranslation(sentence)
            }
            lastProcessedLength = text.count
        }

        // Timer stabilizzazione: se il testo non cambia per 1.5s, traduci il rimanente
        stabilizationTask?.cancel()
        stabilizationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, !Task.isCancelled, self.isRunning else { return }
            let currentText = self.liveTranscription
            guard currentText.count > self.lastProcessedLength else { return }
            let pendingLowerBound = currentText.index(currentText.startIndex, offsetBy: self.lastProcessedLength)
            let pending = String(currentText[pendingLowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !pending.isEmpty {
                self.enqueueTranslation(pending)
                self.lastProcessedLength = currentText.count
            }
        }
    }

    // MARK: - Translation Pipeline

    private func enqueueTranslation(_ text: String) {
        translationStreamContinuation?.yield(text)
    }

    private func performTranslation(of text: String, box: TranslationSessionBox) async {
        isTranslating = true
        updatePhase()
        defer {
            isTranslating = false
            updatePhase()
        }

        do {
            guard isRunning else { return }
            let response = try await box.session.translate(text)
            guard isRunning else { return }

            let prefix = liveTranslation.isEmpty ? "" : " "
            liveTranslation += prefix + response.targetText

            // Limita lunghezza testo tradotto
            if liveTranslation.count > maxTranslationLength {
                let trimIndex = liveTranslation.index(liveTranslation.endIndex, offsetBy: -(maxTranslationLength - 1))
                liveTranslation = "…" + String(liveTranslation[trimIndex...])
            }

            ttsService.enqueue(text: response.targetText, language: targetLanguage.identifier)
            updatePhase()
        } catch {
            os_log("[RealTimeSession] Translation error: %{public}@", log: .default, type: .info, error.localizedDescription)
        }
    }

    // MARK: - Phase & Error

    private func updatePhase() {
        guard errorMessage == nil else {
            phase = .error
            return
        }
        guard isRunning else {
            phase = audioRouteService.isHeadsetConnected ? .idle : .waitingHeadset
            return
        }
        if !audioRouteService.isHeadsetConnected {
            phase = .waitingHeadset
            return
        }
        if isSpeaking {
            phase = .speaking
        } else if isTranslating {
            phase = .translating
        } else {
            phase = .listening
        }
    }

    private func handleError(_ error: Error) {
        phase = .error
        if let convError = error as? ConversationError {
            errorMessage = convError.localizedDescription
        } else {
            errorMessage = error.localizedDescription
        }
    }
}
