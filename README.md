# ReaLang

ReaLang è un'app iOS per la traduzione conversazionale bilingue in tempo reale. Permette a due persone che parlano lingue diverse di comunicare facilmente: ognuno parla nella propria lingua, l'app traduce e legge ad alta voce il messaggio per l'altro interlocutore.

## Funzionamento

1. **Imposta le lingue** — All'avvio, seleziona la lingua di ciascun utente tra le 12 disponibili.
2. **Tieni premuto e parla** — Usa i pulsanti push-to-talk per catturare il parlato.
3. **Ascolta la traduzione** — Il testo viene trascritto, tradotto e letto automaticamente.
4. **Leggi la conversazione** — Lo storico dei messaggi mostra chi ha detto cosa e in quale lingua.

## Requisiti

- iOS 26.0+
- Xcode 16.0+
- Dispositivo fisico iPhone (il riconoscimento vocale live non è supportato su Simulatore)

## Stack Tecnologico

| Componente | Tecnologia |
|------------|------------|
| UI | SwiftUI (Observation) |
| Speech-to-Text | `SFSpeechRecognizer` |
| Traduzione | `Translation` framework |
| Text-to-Speech | `AVSpeechSynthesizer` |
| Audio | `AVAudioEngine` + `AVAudioSession` |
| Generazione progetto | [XcodeGen](https://github.com/yonaskolb/XcodeGen) |

## Build

Il file `project.yml` è la *source of truth* per il progetto Xcode.

```bash
# Rigenera il progetto Xcode (se hai XcodeGen installato)
xcodegen generate

# Build per dispositivo
xcodebuild -project reaLang-native.xcodeproj \
           -scheme reaLangNative \
           -sdk iphoneos \
           -configuration Debug \
           build

# Build per simulatore
xcodebuild -project reaLang-native.xcodeproj \
           -scheme reaLangNative \
           -sdk iphonesimulator \
           -configuration Debug \
           build
```

Per eseguire su dispositivo, apri `reaLang-native.xcodeproj` in Xcode, seleziona il tuo iPhone e premi `Cmd+R`.

## Permessi

All primo avvio l'app richiede:

- **Microfono** — per ascoltare la conversazione.
- **Riconoscimento vocale** — per trascrivere ciò che dici prima di tradurlo.

## Architettura

- **`ConversationSession`** — Stato centrale `@Observable` che gestisce il flusso della conversazione, i permessi e gli errori.
- **`SpeechRecognitionService`** — Gestisce l'autorizzazione del microfono, la registrazione e il riconoscimento vocale.
- **`TextToSpeechService`** — Wrapper attorno ad `AVSpeechSynthesizer` per la sintesi vocale.
- **`ConversationView`** — Schermata principale con la lista messaggi e i controlli push-to-talk.
- **`LanguageSetupView`** — Schermata iniziale per la scelta delle due lingue.

## Lingue supportate

Italiano, Inglese (US/UK), Spagnolo, Francese, Tedesco, Giapponese, Cinese Semplificato, Portoghese (Brasile), Russo, Coreano, Arabo.

## Note

- L'audio del riconoscimento vocale viene inviato ai server Apple a meno che il riconoscimento on-device non sia disponibile per la lingua selezionata.
- I messaggi e le traduzioni rimangono esclusivamente in memoria; non vengono salvati su disco né inviati a server di terze parti.
