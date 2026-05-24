import Foundation
import Testing
@testable import reaLang

@Suite("RealTimeSession")
struct RealTimeSessionTests {
    @MainActor
    @Test("Initial state is correct")
    func initialState() async {
        let session = RealTimeSession(
            sourceLanguage: Locale(identifier: "it_IT"),
            targetLanguage: Locale(identifier: "en_US")
        )

        #expect(!session.isRunning)
        #expect(session.liveTranscription.isEmpty)
        #expect(session.liveTranslation.isEmpty)
        #expect(session.phase == .idle)
        #expect(session.errorMessage == nil)
        #expect(!session.isSpeaking)
    }

    @MainActor
    @Test("Stop when not running does not crash and keeps idle phase")
    func stopWhenNotRunning() async {
        let session = RealTimeSession(
            sourceLanguage: Locale(identifier: "es_ES"),
            targetLanguage: Locale(identifier: "fr_FR")
        )
        session.stop()

        #expect(!session.isRunning)
        #expect(session.phase == .idle)
    }

    @MainActor
    @Test("clearError when no error resets errorMessage to nil")
    func clearErrorWhenNoError() async {
        let session = RealTimeSession(
            sourceLanguage: Locale(identifier: "de_DE"),
            targetLanguage: Locale(identifier: "ja_JP")
        )
        session.clearError()

        #expect(session.errorMessage == nil)
    }

    @MainActor
    @Test("Language assignment is preserved")
    func languageAssignment() async {
        let source = Locale(identifier: "pt_BR")
        let target = Locale(identifier: "ko_KR")
        let session = RealTimeSession(
            sourceLanguage: source,
            targetLanguage: target
        )

        #expect(session.sourceLanguage == source)
        #expect(session.targetLanguage == target)
    }
}
