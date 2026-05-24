import Foundation
import Testing
@testable import reaLang

@Suite("Message")
struct MessageTests {
    @Test("Initialization stores all properties")
    func initialization() {
        let timestamp = Date(timeIntervalSince1970: 0)
        let message = Message(
            originalText: "Ciao",
            translatedText: "Hello",
            sourceLanguage: "it",
            targetLanguage: "en",
            isUserA: true,
            timestamp: timestamp
        )

        #expect(message.originalText == "Ciao")
        #expect(message.translatedText == "Hello")
        #expect(message.sourceLanguage == "it")
        #expect(message.targetLanguage == "en")
        #expect(message.isUserA == true)
        #expect(message.timestamp == timestamp)
    }

    @Test("A message is equal to itself")
    func identityEquality() {
        let message = Message(
            originalText: "Ciao",
            translatedText: "Hello",
            sourceLanguage: "it",
            targetLanguage: "en",
            isUserA: true,
            timestamp: Date()
        )

        #expect(message == message)
    }

    @Test("Different messages are not equal because of unique id")
    func differentMessages() {
        let a = Message(
            originalText: "Ciao",
            translatedText: "Hello",
            sourceLanguage: "it",
            targetLanguage: "en",
            isUserA: true,
            timestamp: Date()
        )
        let b = Message(
            originalText: "Ciao",
            translatedText: "Hello",
            sourceLanguage: "it",
            targetLanguage: "en",
            isUserA: true,
            timestamp: Date()
        )

        #expect(a != b)
    }

    @Test("Different content produces inequality")
    func contentInequality() {
        let a = Message(
            originalText: "Ciao",
            translatedText: "Hello",
            sourceLanguage: "it",
            targetLanguage: "en",
            isUserA: true,
            timestamp: Date()
        )
        let b = Message(
            originalText: "Ciao",
            translatedText: "Hi",
            sourceLanguage: "it",
            targetLanguage: "en",
            isUserA: true,
            timestamp: Date()
        )

        #expect(a != b)
    }
}
