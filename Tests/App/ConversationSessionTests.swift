import Foundation
import Testing
@testable import reaLang

@Suite("ConversationSession")
struct ConversationSessionTests {
    @MainActor
    @Test("Initial state is correct")
    func initialState() async {
        let session = ConversationSession()

        #expect(session.messages.isEmpty)
        #expect(!session.isListeningA)
        #expect(!session.isListeningB)
        #expect(session.errorMessage == nil)
        #expect(session.phase == .idle)
        #expect(session.phaseHistory.isEmpty)
        #expect(session.languageA.identifier == "it_IT")
        #expect(session.languageB.identifier == "en_US")
    }

    @MainActor
    @Test("endConversation resets state and appends idle phase")
    func endConversationResetsState() async {
        let session = ConversationSession()
        session.endConversation()

        #expect(session.messages.isEmpty)
        #expect(!session.isListeningA)
        #expect(!session.isListeningB)
        #expect(session.errorMessage == nil)
        #expect(session.phase == .idle)
        #expect(session.phaseHistory.last?.text.contains("Pronto") == true)
    }

    @MainActor
    @Test("clearError resets error message and phase to idle")
    func clearError() async {
        let session = ConversationSession()
        session.clearError()

        #expect(session.errorMessage == nil)
        #expect(session.phase == .idle)
    }

    @MainActor
    @Test("stopListening resets listening flags")
    func stopListening() async {
        let session = ConversationSession()
        session.stopListening()

        #expect(!session.isListeningA)
        #expect(!session.isListeningB)
    }
}
