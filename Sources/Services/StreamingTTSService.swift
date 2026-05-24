import AVFoundation
import os.log

@MainActor
final class StreamingTTSService: NSObject, @unchecked Sendable, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var queue: [AVSpeechUtterance] = []
    private var isProcessing = false

    private(set) var isSpeaking = false
    var onSpeakingChanged: ((Bool) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public

    func enqueue(text: String, language: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        queue.append(utterance)
        processQueue()
    }

    func clearQueue() {
        queue.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        isProcessing = false
        updateSpeakingState(false)
    }

    func stop() {
        queue.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        isProcessing = false
        updateSpeakingState(false)
    }

    // MARK: - Private

    private func processQueue() {
        guard !isProcessing, !queue.isEmpty else { return }
        isProcessing = true
        let utterance = queue.removeFirst()
        synthesizer.speak(utterance)
        updateSpeakingState(true)
    }

    private func updateSpeakingState(_ value: Bool) {
        if isSpeaking != value {
            isSpeaking = value
            onSpeakingChanged?(value)
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isProcessing = false
            if self.queue.isEmpty {
                self.updateSpeakingState(false)
            }
            self.processQueue()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isProcessing = false
            self.queue.removeAll()
            self.updateSpeakingState(false)
        }
    }
}
