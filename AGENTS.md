# reaLang-native — AI Agent Reference

> **Project:** reaLang-native  
> **App Name:** ReaLang  
> **Platform:** iOS (iPhone only, Portrait)  
> **Target OS:** iOS 26.0+  
> **Language:** Swift 6.0  
> **UI Framework:** SwiftUI  
> **Build Tool:** Xcode 16.0 + XcodeGen  

---

## Project Overview

ReaLang is a real-time bilingual conversation translator for iOS. It enables two people speaking different languages to communicate by:

1. Listening to a speaker via push-to-talk buttons.
2. Transcribing speech using `SFSpeechRecognizer`.
3. Translating the text using Apple's `Translation` framework.
4. Speaking the translated text aloud using `AVSpeechSynthesizer`.
5. Displaying the conversation history in a scrollable message list.
6. **(New)** Providing a continuous real-time translation mode that listens, translates, and speaks without user interaction (requires headset).

The app is designed around a two-user model ("Utente A" and "Utente B"). Each user is assigned a language during setup. The default pair is Italian (`it_IT`) and US English (`en_US`).

---

## Technology Stack

| Component | Technology |
|-----------|------------|
| Language | Swift 6.0 |
| UI | SwiftUI (Observation framework via `@Observable` / `@Bindable`) |
| Speech-to-Text | `Speech.framework` (`SFSpeechRecognizer`) |
| Text-to-Speech | `AVFoundation.framework` (`AVSpeechSynthesizer`) |
| Translation | `Translation.framework` (`TranslationSession`, `LanguageAvailability`) |
| Audio | `AVAudioEngine` + `AVAudioSession` |
| Project Generation | XcodeGen (`project.yml`) |
| IDE | Xcode 16.0 |

**Supported languages** (selectable in the setup screen):  
Italian, English (US/UK), Spanish, French, German, Japanese, Simplified Chinese, Brazilian Portuguese, Russian, Korean, Arabic.

---

## Project Structure

```
reaLang-native/
├── project.yml                    # XcodeGen project spec (source of truth)
├── reaLang-native.xcodeproj/      # Generated Xcode project
├── Sources/
│   ├── App/
│   │   └── ConversationTranslatorApp.swift   # @main entry point
│   ├── Models/
│   │   ├── ConversationSession.swift         # Observable state machine & business logic (push-to-talk)
│   │   ├── RealTimeSession.swift             # Real-time translation orchestration (chunking + pipeline)
│   │   ├── Message.swift                     # Immutable data model for chat bubbles
│   │   └── ConversationError.swift           # LocalizedError enum (Italian strings)
│   ├── Services/
│   │   ├── SpeechRecognitionService.swift    # Mic auth, recording, speech recognition (push-to-talk)
│   │   ├── StreamingSpeechService.swift      # Continuous speech-to-text with auto-restart
│   │   ├── TextToSpeechService.swift         # AVSpeechSynthesizer wrapper
│   │   ├── StreamingTTSService.swift         # Queued TTS with speaking-state tracking
│   │   └── AudioRouteService.swift           # Headset / external audio detection
│   └── Views/
│       ├── LanguageSetupView.swift           # Language picker + two side-by-side action buttons
│       ├── ConversationView.swift            # Main chat + push-to-talk controls
│       ├── RealTimeTranslationView.swift     # Real-time translation UI (live text + start/stop)
│       ├── MessageBubbleView.swift           # Individual chat bubble UI
│       └── PushToTalkButton.swift            # Hold-to-talk button with gesture
├── Resources/
│   ├── Info.plist                 # Bundle config + microphone/speech usage descriptions
│   ├── LaunchScreen.storyboard    # Static launch screen ("ReaLang" label)
│   └── Assets.xcassets/           # App icon assets
└── build/                         # xcodebuild output (ignored from source control)
```

---

## Build and Run

### Prerequisites
- macOS with Xcode 16.0+
- iOS 26.0 SDK
- (Optional) [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed if you need to regenerate the `.xcodeproj`

### Regenerate the Xcode project
If `project.yml` changes, regenerate the project:

```bash
xcodegen generate
```

### Build from the command line

```bash
xcodebuild -project reaLang-native.xcodeproj \
           -scheme reaLangNative \
           -sdk iphoneos \
           -configuration Debug \
           build
```

For the simulator:

```bash
xcodebuild -project reaLang-native.xcodeproj \
           -scheme reaLangNative \
           -sdk iphonesimulator \
           -configuration Debug \
           build
```

### Run on device
Open `reaLang-native.xcodeproj` in Xcode, select a connected iPhone, and run (`Cmd+R`).

The app can also be deployed wirelessly to a paired device via `devicectl`:

```bash
xcrun devicectl device install app --device <DeviceName> <path/to/reaLang.app>
```

> **Note:** The app requires a physical iOS device for speech recognition. The simulator may not support `SFSpeechRecognizer` live recording.

---

## Code Style Guidelines

- **Swift 6 features:** Use `@Observable` (not `ObservableObject`) for state. Use `@Bindable` in views when bindings are needed.
- **Concurrency:** All services and the session are marked `@MainActor`. Avoid escaping non-`Sendable` closures across isolation boundaries.
- **Comments:** Use `// MARK: - Section Name` to group related methods (e.g., `// MARK: - Permissions`, `// MARK: - Subviews`).
- **Naming:** Follow standard Swift naming (`PascalCase` for types, `camelCase` for members). View structs end in `View`, service classes end in `Service`.
- **Localization:** User-facing strings in the UI, errors, and `Info.plist` descriptions are written in **Italian**. New user-facing text should continue in Italian for consistency.
- **Accessibility:** Add `accessibilityLabel` and `accessibilityHint` to interactive custom views (see `PushToTalkButton` and `MessageBubbleView` for examples).

---

## Architecture Notes

### State Management
- `ConversationSession` is the single source of truth for push-to-talk mode. It is `@Observable` and injected into views as a shared reference.
- `LanguageSetupView` owns the `NavigationStack` and pushes `ConversationView` or `RealTimeTranslationView` onto the path.
- Listening state in push-to-talk is tracked by two booleans: `isListeningA` and `isListeningB`. Only one side can listen at a time.

### Language Setup UI
The setup screen presents two language pickers and two side-by-side buttons at the bottom (`HStack` inside `.safeAreaInset(edge: .bottom)`):
- **"Conversazione"** (`bubble.left.and.bubble.right.fill`, `.borderedProminent`) → opens `ConversationView`.
- **"Real-Time"** (`bolt.fill`, `.bordered`) → opens `RealTimeTranslationView`. Disabled if languages are identical or if no headset is connected.

### Conversation Flow (Push-to-Talk)
1. User holds a `PushToTalkButton`.
2. `ConversationSession.startListening(userA:)` requests microphone + speech permissions.
3. `SpeechRecognitionService.startRecording(language:)` captures audio and returns transcribed text.
4. `LanguageAvailability` checks that the source/target pair is supported.
5. `TranslationSession` translates the text.
6. A `Message` is appended to `messages`.
7. `TextToSpeechService.speak(text:language:)` reads the translation aloud.

### Real-Time Translation Flow
1. User taps the green play button in `RealTimeTranslationView`.
2. `RealTimeSession.start()` verifies headset connection and language availability.
3. Creates a persistent `TranslationSession` and starts an `AsyncStream<String>` pipeline.
4. `StreamingSpeechService` begins continuous recognition with auto-restart on transient errors.
5. Transcribed text is chunked by punctuation or stabilized after 1.5 s of silence.
6. Each chunk is translated and enqueued to `StreamingTTSService` for sequential playback.
7. The session stops automatically on `onDisappear`, background scene phase, or manual stop.

### Error Handling
- `ConversationError` covers authorization failures, unsupported translation pairs, and recognition errors.
- Errors surface in the UI via the `errorMessage` optional on `ConversationSession` / `RealTimeSession`, displayed as a SwiftUI `.alert`.

---

## Permissions

The app requires two runtime permissions. Descriptions are defined in `Resources/Info.plist`:

- **Microphone** (`NSMicrophoneUsageDescription`)  
  "L'app usa il microfono per ascoltare e tradurre la conversazione in tempo reale."

- **Speech Recognition** (`NSSpeechRecognitionUsageDescription`)  
  "L'app usa il riconoscimento vocale per trascrivere ciò che dici prima di tradurlo."

When adding new permission requirements, always provide Italian usage descriptions in `Info.plist`.

---

## Testing

- **Test target:** `reaLangNativeTests` (Swift Testing) — defined in `project.yml`, sources under `Tests/`.
- **Run tests from the command line:**
  ```bash
  xcodebuild -project reaLang-native.xcodeproj \
             -scheme reaLangNative \
             -sdk iphonesimulator \
             -destination 'platform=iOS Simulator,name=iPhone 17' \
             test
  ```
- **Manual testing checklist:**
  1. Grant microphone and speech permissions on first launch.
  2. Select two different languages on the setup screen.
  3. Verify both "Conversazione" and "Real-Time" buttons are visible side-by-side at the bottom.
  4. Tap "Conversazione", hold "Utente A" button, speak, release, and verify translation + TTS.
  5. Hold "Utente B" button, speak, release, and verify reverse translation + TTS.
  6. Tap "Fine" or "Termina Conversazione" and verify the message list clears.
  7. Connect a headset, return to setup, tap "Real-Time", and verify the status indicators animate.
  8. Speak while Real-Time is running and verify transcription, translation, and TTS output.
  9. Rotate device — iPhone should stay locked to portrait.

---

## Deployment

- **Bundle ID:** `com.realang.realang-native`
- **Product Name:** `reaLang`
- **Version:** `1.0` (Build `1`)
- **Target Device Family:** iPhone (`1`)
- **Supported Orientations:** Portrait on iPhone; all orientations on iPad (per `Info.plist`)
- **Mac Catalyst:** Disabled
- **Mac Designed for iPhone/iPad:** Disabled

For App Store distribution, update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`, archive via Xcode, and submit through App Store Connect.

---

## Security Considerations

- Speech audio is streamed to Apple's speech recognition servers unless the recognizer locale supports on-device recognition. Do not log or persist raw audio buffers.
- Transcription text and translations are stored only in-memory inside `ConversationSession.messages` / `RealTimeSession`. No data is written to disk or sent to third-party servers.
- If adding cloud translation or analytics later, ensure user consent and a privacy policy are in place.

---

## Useful References

- [XcodeGen Documentation](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
- [Apple Translation Framework](https://developer.apple.com/documentation/translation)
- [Apple Speech Framework](https://developer.apple.com/documentation/speech)
- [SwiftUI Observation](https://developer.apple.com/documentation/observation)
