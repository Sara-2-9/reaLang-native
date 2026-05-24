import AVFoundation
import Speech
import os.log

final class SpeechRecognitionService: @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var finalResult: String?
    private var recordingContinuation: CheckedContinuation<String, Error>?
    private var shouldCancelRecording = false
    private let lock = NSRecursiveLock()

    // MARK: - Permissions

    nonisolated func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    nonisolated func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Recording

    func startRecording(language: Locale) async throws -> String {
        os_log("[SpeechService] startRecording called for %{public}@", log: .default, type: .info, language.identifier)
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }

            if shouldCancelRecording {
                shouldCancelRecording = false
                os_log("[SpeechService] Cancelled before start", log: .default, type: .info)
                continuation.resume(returning: "")
                return
            }

            if let oldContinuation = recordingContinuation {
                os_log("[SpeechService] Cleaning up stale continuation from previous session", log: .default, type: .info)
                recordingContinuation = nil
                oldContinuation.resume(returning: "")
            }

            recordingContinuation = continuation
            finalResult = nil
            os_log("[SpeechService] Continuation stored, finalResult cleared", log: .default, type: .info)

            guard let recognizer = SFSpeechRecognizer(locale: language), recognizer.isAvailable else {
                os_log("[SpeechService] ERROR: recognizer not available for %{public}@", log: .default, type: .info, language.identifier)
                self.finishRecording(error: ConversationError.recognitionFailed("Riconoscimento non disponibile per \(language.identifier). Verifica che la lingua sia supportata."))
                return
            }

            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                os_log("[SpeechService] ERROR: audioSession setup failed: %{public}@", log: .default, type: .info, error.localizedDescription)
                self.finishRecording(error: ConversationError.recognitionFailed(error.localizedDescription))
                return
            }

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let request = recognitionRequest else {
                os_log("[SpeechService] ERROR: failed to create recognition request", log: .default, type: .info)
                self.finishRecording(error: ConversationError.recognitionFailed("Impossibile creare la richiesta di riconoscimento"))
                return
            }
            request.shouldReportPartialResults = true

            os_log("[SpeechService] Starting recognition task", log: .default, type: .info)
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }

                if let result = result {
                    self.lock.lock()
                    self.finalResult = result.bestTranscription.formattedString
                    self.lock.unlock()
                    os_log("[SpeechService] Partial result: %{public}@, isFinal: %{public}d", log: .default, type: .info, result.bestTranscription.formattedString, result.isFinal)
                    if result.isFinal {
                        self.finishRecording()
                    }
                }

                if let error = error {
                    self.lock.lock()
                    let hasResult = self.finalResult != nil
                    self.lock.unlock()
                    os_log("[SpeechService] Recognition error: %{public}@", log: .default, type: .info, error.localizedDescription)
                    self.finishRecording(error: ConversationError.recognitionFailed(self.mapRecognizerError(error, hasPartialResult: hasResult)))
                } else if result == nil {
                    os_log("[SpeechService] Callback with nil result and nil error (cancelled)", log: .default, type: .info)
                    self.finishRecording()
                }
            }

            let engine = AVAudioEngine()
            self.audioEngine = engine
            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                os_log("[SpeechService] ERROR: invalid audio format", log: .default, type: .info)
                self.finishRecording(error: ConversationError.recognitionFailed("Formato audio non valido sul dispositivo"))
                return
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }

            engine.prepare()
            do {
                try engine.start()
                os_log("[SpeechService] Audio engine started", log: .default, type: .info)
            } catch {
                os_log("[SpeechService] ERROR: engine start failed: %{public}@", log: .default, type: .info, error.localizedDescription)
                self.finishRecording(error: ConversationError.recognitionFailed(error.localizedDescription))
            }
        }
    }

    func stopRecording() {
        lock.lock()
        let wasRecording = recordingContinuation != nil
        let partialText = finalResult ?? ""
        if !wasRecording {
            shouldCancelRecording = true
            os_log("[SpeechService] stopRecording: no active recording, setting shouldCancelRecording", log: .default, type: .info)
        } else {
            os_log("[SpeechService] stopRecording: active recording found, finalResult: '%{public}@'", log: .default, type: .info, partialText)
        }
        lock.unlock()

        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        audioEngine?.stop()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            os_log("[SpeechService] WARNING: audioSession deactivate failed: %{public}@", log: .default, type: .info, error.localizedDescription)
        }

        lock.lock()
        defer { lock.unlock() }
        if let continuation = recordingContinuation {
            os_log("[SpeechService] Resuming continuation with partial text: '%{public}@'", log: .default, type: .info, partialText)
            recordingContinuation = nil
            continuation.resume(returning: partialText)
        } else {
            os_log("[SpeechService] Continuation already cleared by finishRecording", log: .default, type: .info)
        }
    }

    // MARK: - Private

    private func finishRecording(error: Error? = nil) {
        lock.lock()
        defer { lock.unlock() }

        guard let continuation = recordingContinuation else {
            os_log("[SpeechService] finishRecording: no continuation to resume", log: .default, type: .info)
            return
        }
        recordingContinuation = nil
        os_log("[SpeechService] finishRecording: continuation cleared", log: .default, type: .info)

        if let error = error {
            os_log("[SpeechService] finishRecording: resuming with error", log: .default, type: .info)
            continuation.resume(throwing: error)
        } else {
            os_log("[SpeechService] finishRecording: resuming with result: '%{public}@'", log: .default, type: .info, finalResult ?? "")
            continuation.resume(returning: finalResult ?? "")
        }
    }

    private func mapRecognizerError(_ error: Error, hasPartialResult: Bool) -> String {
        let nsError = error as NSError
        if nsError.domain == "kAFAssistantErrorDomain" {
            switch nsError.code {
            case 216:
                return "Il riconoscimento vocale non è disponibile per questa lingua. Verifica la connessione o prova con un'altra lingua."
            case 203:
                return "Connessione di rete assente. Il riconoscimento vocale richiede una connessione per alcune lingue."
            case 1107:
                return "Timeout del riconoscimento. Nessun audio rilevato."
            default:
                return "Errore riconoscimento vocale (\(nsError.code)): \(error.localizedDescription)"
            }
        }
        if hasPartialResult {
            return "Riconoscimento interrotto."
        }
        return error.localizedDescription
    }
}
