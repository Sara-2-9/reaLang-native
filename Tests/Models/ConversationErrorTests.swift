import Foundation
import Testing
@testable import reaLang

@Suite("ConversationError")
struct ConversationErrorTests {
    @Test("Speech not authorized localized description")
    func speechNotAuthorizedDescription() {
        let error = ConversationError.speechNotAuthorized
        #expect(error.localizedDescription == "Autorizzazione riconoscimento vocale negata.")
    }

    @Test("Microphone not authorized localized description")
    func microphoneNotAuthorizedDescription() {
        let error = ConversationError.microphoneNotAuthorized
        #expect(error.localizedDescription == "Autorizzazione microfono negata.")
    }

    @Test("Translation not supported localized description")
    func translationNotSupportedDescription() {
        let error = ConversationError.translationNotSupported
        #expect(error.localizedDescription == "Traduzione non supportata per questa coppia di lingue. Verifica che il dispositivo supporti Apple Intelligence e che i modelli di traduzione siano disponibili.")
    }

    @Test("Recognition failed localized description carries message")
    func recognitionFailedDescription() {
        let error = ConversationError.recognitionFailed("Test di errore")
        #expect(error.localizedDescription == "Test di errore")
    }
}
