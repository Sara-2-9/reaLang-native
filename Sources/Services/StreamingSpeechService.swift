import AVFoundation
import Speech
import os.log

private final class AudioTapHandler: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func setRequest(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func handle(buffer: AVAudioPCMBuffer) {
        lock.lock()
        request?.append(buffer)
        lock.unlock()
    }
}

@MainActor
final class StreamingSpeechService: @unchecked Sendable {
    var onResult: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var accumulatedText = ""
    private var currentPartial = ""
    private let lock = NSRecursiveLock()
    private var isStopping = false
    private var currentRecognizer: SFSpeechRecognizer?
    private var restartAttempts = 0
    private let maxRestartDelay: TimeInterval = 5.0
    private let maxAccumulatedLength = 10000
    private var interruptionObserver: NSObjectProtocol?
    private var tapHandler: AudioTapHandler?

    // MARK: - Lifecycle

    nonisolated private static func makeTapClosure(handler: AudioTapHandler) -> (AVAudioPCMBuffer, AVAudioTime) -> Void {
        return { buffer, _ in
            handler.handle(buffer: buffer)
        }
    }

    func startContinuousRecognition(language: Locale) async throws {
        isStopping = false
        accumulatedText = ""
        currentPartial = ""
        currentRecognizer = nil
        restartAttempts = 0

        let micAuthorized = await requestMicrophoneAuthorization()
        let speechAuthorized = await requestSpeechAuthorization()
        guard micAuthorized && speechAuthorized else {
            throw ConversationError.microphoneNotAuthorized
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw ConversationError.recognitionFailed(error.localizedDescription)
        }

        guard let recognizer = SFSpeechRecognizer(locale: language), recognizer.isAvailable else {
            throw ConversationError.recognitionFailed("Riconoscimento non disponibile per \(language.identifier)")
        }
        currentRecognizer = recognizer

        let engine = AVAudioEngine()
        audioEngine = engine
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw ConversationError.recognitionFailed("Formato audio non valido sul dispositivo")
        }

        let handler = AudioTapHandler()
        self.tapHandler = handler
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat, block: Self.makeTapClosure(handler: handler))

        engine.prepare()
        try engine.start()
        os_log("[StreamingSpeech] Audio engine started", log: .default, type: .info)

        startNewRecognitionTask()
        registerInterruptionObserver()
    }

    func stopContinuousRecognition() {
        isStopping = true
        os_log("[StreamingSpeech] Stopping recognition", log: .default, type: .info)

        unregisterInterruptionObserver()

        lock.lock()
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        lock.unlock()

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        lock.lock()
        recognitionTask = nil
        recognitionRequest = nil
        tapHandler = nil
        lock.unlock()

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            os_log("[StreamingSpeech] WARNING: deactivate failed: %{public}@", log: .default, type: .info, error.localizedDescription)
        }
    }

    // MARK: - Interruption Handling

    private func registerInterruptionObserver() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            let options = (userInfo[AVAudioSessionInterruptionOptionKey] as? UInt).flatMap { AVAudioSession.InterruptionOptions(rawValue: $0) }
            Task { @MainActor in
                self.handleInterruption(type: type, options: options)
            }
        }
    }

    private func unregisterInterruptionObserver() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
    }

    private func handleInterruption(type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions?) {
        switch type {
        case .began:
            guard !isStopping else { return }
            os_log("[StreamingSpeech] Audio interruption began", log: .default, type: .info)
            audioEngine?.stop()
            lock.lock()
            recognitionTask?.cancel()
            lock.unlock()
        case .ended:
            guard !isStopping else { return }
            guard let options = options, options.contains(.shouldResume) else { return }
            os_log("[StreamingSpeech] Audio interruption ended, resuming", log: .default, type: .info)
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                try audioEngine?.start()
                startNewRecognitionTask()
            } catch {
                os_log("[StreamingSpeech] Failed to resume after interruption: %{public}@", log: .default, type: .info, error.localizedDescription)
                DispatchQueue.main.async { [weak self] in
                    self?.onError?(error)
                }
            }
        @unknown default:
            break
        }
    }

    // MARK: - Private

    private func startNewRecognitionTask() {
        lock.lock()
        defer { lock.unlock() }

        guard !isStopping, let recognizer = currentRecognizer else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request
        tapHandler?.setRequest(request)

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                self.lock.lock()
                self.currentPartial = text
                let fullText = self.accumulatedText.isEmpty ? text : self.accumulatedText + " " + text
                self.lock.unlock()

                DispatchQueue.main.async {
                    self.onResult?(fullText, result.isFinal)
                }

                if result.isFinal {
                    self.lock.lock()
                    if !text.isEmpty {
                        self.accumulatedText = self.accumulatedText.isEmpty ? text : self.accumulatedText + " " + text
                        // Truncate if too long
                        if self.accumulatedText.count > self.maxAccumulatedLength {
                            let trimIndex = self.accumulatedText.index(self.accumulatedText.endIndex, offsetBy: -(self.maxAccumulatedLength - 1))
                            self.accumulatedText = "…" + String(self.accumulatedText[trimIndex...])
                        }
                    }
                    self.currentPartial = ""
                    self.restartAttempts = 0
                    self.lock.unlock()
                    self.restartTaskAfterDelay()
                }
            }

            if let error = error {
                self.handleRecognitionError(error)
            } else if result == nil {
                // nil result senza errore → riavvia se non stiamo fermando
                self.restartTaskAfterDelay()
            }
        }
    }

    private func handleRecognitionError(_ error: Error) {
        let nsError = error as NSError
        // Errori di cancellazione interna possono essere ignorati
        if nsError.domain == "kAFAssistantErrorDomain" {
            switch nsError.code {
            case 216, 203, 1110, 1111:
                // Timeout, rete, ecc.
                break
            case 301:
                // Cancellato dall'utente
                if isStopping { return }
            default:
                break
            }
        }

        lock.lock()
        if !currentPartial.isEmpty {
            accumulatedText = accumulatedText.isEmpty ? currentPartial : accumulatedText + " " + currentPartial
            if accumulatedText.count > maxAccumulatedLength {
                let trimIndex = accumulatedText.index(accumulatedText.endIndex, offsetBy: -(maxAccumulatedLength - 1))
                accumulatedText = "…" + String(accumulatedText[trimIndex...])
            }
            currentPartial = ""
        }
        let shouldRestart = !isStopping
        lock.unlock()

        if shouldRestart {
            restartTaskAfterDelay()
        } else {
            DispatchQueue.main.async {
                self.onError?(error)
            }
        }
    }

    private func restartTaskAfterDelay() {
        let delay = min(0.2 * pow(2.0, Double(restartAttempts)), maxRestartDelay)
        restartAttempts += 1
        os_log("[StreamingSpeech] Restarting after %{public}f seconds (attempt %d)", log: .default, type: .info, delay, restartAttempts)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startNewRecognitionTask()
        }
    }

    // MARK: - Permissions

    nonisolated private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    nonisolated private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
