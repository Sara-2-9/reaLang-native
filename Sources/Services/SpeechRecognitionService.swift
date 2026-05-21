import AVFoundation
import Speech

@MainActor
final class SpeechRecognitionService {
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var finalResult: String?
    private var continuationResumed = false

    // MARK: - Permissions

    func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Recording

    func startRecording(language: Locale) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            guard let recognizer = SFSpeechRecognizer(locale: language), recognizer.isAvailable else {
                continuation.resume(throwing: ConversationError.recognitionFailed("Riconoscimento non disponibile per \(language.identifier)"))
                return
            }

            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                continuation.resume(throwing: ConversationError.recognitionFailed(error.localizedDescription))
                return
            }

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let request = recognitionRequest else {
                continuation.resume(throwing: ConversationError.recognitionFailed("Impossibile creare la richiesta di riconoscimento"))
                return
            }
            request.shouldReportPartialResults = true

            finalResult = nil
            continuationResumed = false

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }

                Task { @MainActor [weak self] in
                    guard let self = self else { return }

                    if let result = result {
                        self.finalResult = result.bestTranscription.formattedString
                        if result.isFinal {
                            self.finishRecording(continuation: continuation)
                        }
                    }

                    if let error = error {
                        self.finalResult = self.finalResult ?? ""
                        self.finishRecording(continuation: continuation, error: error)
                    }
                }
            }

            let engine = AVAudioEngine()
            self.audioEngine = engine
            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }

            engine.prepare()
            do {
                try engine.start()
            } catch {
                self.finishRecording(continuation: continuation, error: error)
            }
        }
    }

    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Ignore cleanup errors
        }
    }

    // MARK: - Private

    private func finishRecording(
        continuation: CheckedContinuation<String, Error>,
        error: Error? = nil
    ) {
        guard !continuationResumed else { return }
        continuationResumed = true
        stopRecording()

        if let error = error {
            continuation.resume(throwing: ConversationError.recognitionFailed(error.localizedDescription))
        } else {
            continuation.resume(returning: finalResult ?? "")
        }
    }
}
