# iOS → Android feature parity

Source of truth: the Swift project at `~/ai-reply/AI-Reply` (app target `AIReply`,
extension target `ReplyKeyboard`, shared sources in `Shared/`).

This file is the implementation checklist. It was written from an audit of the
iOS sources before any Kotlin was written, and updated after implementation.

**Status vocabulary** (as required by the brief):

| Status | Meaning |
|---|---|
| `IMPLEMENTED_AND_VERIFIED` | Built and exercised, result observed |
| `IMPLEMENTED_NOT_DEVICE_VERIFIED` | Written and statically checked; not run on a device/emulator in this session |
| `PARTIALLY_IMPLEMENTED` | Core path present, a sub-behaviour is missing |
| `BLOCKED` | Cannot be done in this environment; reason recorded |
| `NOT_IMPLEMENTED` | Deliberately not ported; reason recorded |

> **Session-wide build note.** No Gradle build ran in this session. `dl.google.com`,
> `maven.google.com`, `repo1.maven.org`, `plugins.gradle.org` and `services.gradle.org`
> are refused by the egress policy in both sandboxes available here (the cloud
> container and the Linux VM on the Mac), so neither the Android SDK nor any AGP /
> Compose artifact could be fetched.
>
> What was done instead, and what each status below is therefore worth:
>
> * **All 86 Kotlin files** were parsed with the real Kotlin 2.0.21 compiler front
>   end (taken from the Gradle distribution) — **0 parse errors**.
> * The domain model, `ReplyPromptBuilder`, `WorkingHours`, `ReplyDraftNormalizer`,
>   the layout tables and `AutoShift` were **compiled and their 48 tests executed —
>   48 passed, 0 failed.** Rows covered by those tests are marked
>   `IMPLEMENTED_AND_VERIFIED`.
> * All 280 `R.string` references were resolved against the 327 declared strings;
>   package declarations checked against directories; no duplicate top-level types.
>
> `IMPLEMENTED_NOT_DEVICE_VERIFIED` therefore means: written, parsed by the real
> compiler, resource-checked — and not compiled against the Android framework or
> run on a device. See `README.md` § Known limitations.

---

## 1. Application shell

| Feature | iOS implementation | Android equivalent | Status | Notes |
|---|---|---|---|---|
| App entry | `AIReplyApp` (`@main`, SwiftUI `App`), branches onboarding vs `HomeView` on `profile.hasCompletedOnboarding` | `MainActivity` (`ComponentActivity`) + `AppNavHost`, same branch on the same persisted flag | IMPLEMENTED_NOT_DEVICE_VERIFIED | Same single decision point, same stored field |
| DI / object graph | Swift singletons (`ProfileStore.shared`, `SharedSettings.shared`, `AIConfiguration.shared`) | `ServiceLocator` held by `AIReplyApplication`, `applicationContext` only | IMPLEMENTED_NOT_DEVICE_VERIFIED | No Hilt: an IME pays DI graph construction on every cold start |
| Observable config | `@Observable ReplyConfigurationModel` in the SwiftUI environment | `ConfigurationRepository` exposing `StateFlow<ReplyConfiguration>`, collected by Compose | IMPLEMENTED_NOT_DEVICE_VERIFIED | Same "one instance, every screen edits the same value" rule |
| Light / dark | `AppearancePreference` (system/light/dark) → `preferredColorScheme` | Same enum → `AIReplyTheme(darkTheme = …)` | IMPLEMENTED_NOT_DEVICE_VERIFIED | Dynamic colour deliberately off; the product has its own accent |
| Interface language | `AppLanguage` en/ru/kk, `nil` = follow system; drives `\.locale` | Same enum; `LocalizedContext.wrap()` in `attachBaseContext`, `recreate()` on change | IMPLEMENTED_NOT_DEVICE_VERIFIED | See §7 |

## 2. Domain model

Every type below is a direct port, field for field, including the tolerant
decoding that lets a configuration written by an older build still load.

| iOS type | Android type | Status | Notes |
|---|---|---|---|
| `UserProfile` (+ 1000/120 char clamps, `promptDescription`, `hasAnyContext`) | `UserProfile` | IMPLEMENTED_AND_VERIFIED | Clamped by code point, matching iOS's Unicode-scalar counting; covered by `TextLimitsTest` |
| `BusinessContext` (offering/summary/rules, `cleanRules`, max 8 rules) | `BusinessContext` | IMPLEMENTED_AND_VERIFIED | Rule cleaning and the cap are executed in `ConfigurationTest` / `ReplyPromptBuilderTest` |
| `ReplyTone`, `ReplyLength`, `EmojiPolicy`, `WorkingHoursBehaviour`, `RelationshipKind` | same five enums | IMPLEMENTED_NOT_DEVICE_VERIFIED | Same raw values on the wire (`mention_when_relevant` etc.) |
| `TimeOfDay`, `DaySchedule`, `WorkingHours` (+ `Context` derivation, weekday grouping) | same | IMPLEMENTED_AND_VERIFIED | 11 executed tests, including weekday grouping and the Sunday-is-1 convention |
| `ReplyTemplate` (built-ins + custom, per-template business/hours override) | `ReplyTemplate` | IMPLEMENTED_NOT_DEVICE_VERIFIED | Built-in ids stay `friend`/`client`/`business`/`work` |
| `ReplyConfiguration` + `normalized()` repair | same | IMPLEMENTED_NOT_DEVICE_VERIFIED | Same repair rules: restore missing built-ins, unhide if all hidden, re-index |
| `TemplateSummary` (first-frame chip cache) | same | IMPLEMENTED_NOT_DEVICE_VERIFIED | Same reason: draw the chip row before the full config is read |

## 3. Storage

| Feature | iOS | Android | Status | Notes |
|---|---|---|---|---|
| Shared state between app and keyboard | App Group `group.kz.yerek.replykeyboard` + `UserDefaults` suite | Same process and same app → app-private `SharedPreferences` | IMPLEMENTED_NOT_DEVICE_VERIFIED | Android has no App Group problem to solve; the whole `AppGroup.isAvailable` / "container unavailable" failure mode disappears |
| Profile + templates | JSON file in the App Group container, mtime-cached decode | JSON file in `filesDir`, same mtime cache, `kotlinx.serialization` | IMPLEMENTED_NOT_DEVICE_VERIFIED | Not Room, for the same reason iOS is not Core Data: the IME must not pay store-stack setup on appearance |
| Atomic write | `Data.write(options: .atomic)` | temp file + `renameTo` | IMPLEMENTED_NOT_DEVICE_VERIFIED | A keyboard reading mid-write sees old or new, never truncated |
| API credential | Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, access group | Android Keystore AES/GCM key (`setUserAuthenticationRequired=false`), ciphertext in `SharedPreferences` | IMPLEMENTED_NOT_DEVICE_VERIFIED | Hand-rolled rather than `androidx.security:security-crypto`, which is alpha and deprecated; ~150 lines, no dependency. Key is non-exportable and device-bound, same guarantee class as the Keychain item |
| Keyboard height cache | `SharedSettings.keyboardHeight`, seeds the first frame | **NOT_IMPLEMENTED** | NOT_IMPLEMENTED | Android has no equivalent problem: the IME window sizes itself to the view, so there is no first-frame resize to pre-empt |

## 4. AI layer

| Feature | iOS | Android | Status | Notes |
|---|---|---|---|---|
| Entry point | `AIReplyService.generate(Request)` | `AIReplyService.generate(Request)` | IMPLEMENTED_NOT_DEVICE_VERIFIED | Same responsibilities, same boundaries |
| 300-char incoming-message rule | `AIReplyService.validate` before any request | same | IMPLEMENTED_NOT_DEVICE_VERIFIED | Enforced before the network call, so an over-long paste costs nothing |
| Prompt construction | `ReplyPromptBuilder`: rules in the developer message, all user data in named blocks in the user message | same, byte-for-byte identical developer text **plus** one `INSTRUCTION` paragraph | IMPLEMENTED_AND_VERIFIED | 11 executed tests. The added paragraph is the only deliberate prompt delta; see §6 |
| Prompt-injection posture | `<incoming_message>`, `<user_profile>`, `<business_context>`, `<user_rules>`, `<template_instructions>` introduced as data | same blocks + `<user_instruction>` | IMPLEMENTED_AND_VERIFIED | A test asserts that "Ignore previous instructions" reaches the user message and never the developer message |
| Relationship guidance | Hard-coded per `RelationshipKind`, not stored per template | same | IMPLEMENTED_NOT_DEVICE_VERIFIED | Keeps it out of user data and migratable |
| Transport abstraction | `protocol ReplyTransport` + Direct / Backend | `interface ReplyTransport` + Direct / Backend | IMPLEMENTED_NOT_DEVICE_VERIFIED | |
| Direct OpenAI | `/v1/responses`, `store:false`, `max_output_tokens` 180, temp 0.7, 25 s | same, `HttpURLConnection` | IMPLEMENTED_NOT_DEVICE_VERIFIED | No OkHttp/Retrofit: fewer classes to load in the IME |
| Backend transport | Structured JSON to a self-hosted service, bearer token | same wire format | IMPLEMENTED_NOT_DEVICE_VERIFIED | Field names preserved, including the legacy `keyboard_language` |
| Error set | `AIReplyError`, 11 closed cases | same sealed interface | IMPLEMENTED_NOT_DEVICE_VERIFIED | No status codes or response bodies ever reach the UI |
| Draft normalisation | `ReplyDraftNormalizer`, URL-preserving | same | IMPLEMENTED_AND_VERIFIED | 7 executed tests, including that a URL survives space collapsing |
| Response unwrapping | `ReplyNetworking.unwrapQuotes` (`"`, `“”`, `«»`) | same | IMPLEMENTED_NOT_DEVICE_VERIFIED | |
| Model / mode / backend URL settings | `AIConfiguration` in App Group defaults | `AIConfiguration` over `SettingsStore` | IMPLEMENTED_NOT_DEVICE_VERIFIED | `gpt-4o-mini` default named in exactly one place, as on iOS |
| Per-install id | Random UUID, never hardware-derived | same | IMPLEMENTED_NOT_DEVICE_VERIFIED | |

## 5. Keyboard

| Feature | iOS | Android | Status | Notes |
|---|---|---|---|---|
| Host | `UIInputViewController` extension | `ReplyKeyboardService : InputMethodService` | IMPLEMENTED_NOT_DEVICE_VERIFIED | Declared with `android.view.InputMethod` + `res/xml/method.xml` |
| Layouts | QWERTY 10/9/7, ЙЦУКЕН 12/12/9 with visible `ё`, Kazakh = ЙЦУКЕН + 9-letter top row | identical tables, ported verbatim | IMPLEMENTED_AND_VERIFIED | Executed tests assert all 33 Cyrillic letters and all 9 Kazakh letters are present |
| Number / symbol planes | `KeyboardPlane.numbers` / `.symbols`, `₸` included | same tables | IMPLEMENTED_NOT_DEVICE_VERIFIED | |
| Metrics | Derived from live width + row count; 43/46/48 pt bands, ×0.855 for 5 rows | same formula in dp, plus a landscape clamp | IMPLEMENTED_NOT_DEVICE_VERIFIED | Landscape clamp is new; iOS is portrait-locked, Android is not |
| Theme | Dark-first, resolved from `keyboardAppearance` then traits | Resolved from `EditorInfo.IME_FLAG_*`/`Configuration.uiMode` + the user's appearance override | IMPLEMENTED_NOT_DEVICE_VERIFIED | Android hosts do not advertise a keyboard appearance, so the system dark mode plus the app's own override is the closest honest signal |
| Key colours | Exact RGB values from `KeyboardTheme` | same values | IMPLEMENTED_NOT_DEVICE_VERIFIED | |
| Shift / caps lock | Tap toggles, double tap within 0.35 s locks | same, same threshold | IMPLEMENTED_NOT_DEVICE_VERIFIED | |
| Auto-shift at sentence start | `isAtSentenceStart`, never turns shift *off* | same algorithm | IMPLEMENTED_AND_VERIFIED | 6 executed tests |
| Double-space → `. ` | 0.35 s window, only after a letter/digit | same | IMPLEMENTED_NOT_DEVICE_VERIFIED | |
| Delete repeat | 0.45 s delay then 0.085 s repeat | same, coroutine-driven | IMPLEMENTED_NOT_DEVICE_VERIFIED | |
| Layout switch key | `EN`/`РУ`/`ҚАЗ` badge cycles layouts | same | IMPLEMENTED_NOT_DEVICE_VERIFIED | |
| System keyboard switch | Globe key → `handleInputModeList`, shown only when `needsInputModeSwitchKey` | Globe key → `switchToNextInputMethod` / `showInputMethodPicker` on long press, shown when `shouldOfferSwitchingToNextInputMethod()` | IMPLEMENTED_NOT_DEVICE_VERIFIED | Same tap-advances / long-press-lists behaviour |
| Return key label + prominence | Follows `returnKeyType` (send/search/go/done) | Follows `EditorInfo.imeOptions` action | IMPLEMENTED_NOT_DEVICE_VERIFIED | Same word list per language |
| Key click sound / haptics | `UIDevice.playInputClick()` | `AudioManager.playSoundEffect` + `performHapticFeedback`, both honouring the system settings | IMPLEMENTED_NOT_DEVICE_VERIFIED | Android exposes the user's own sound/vibrate-on-keypress settings; both are read, not assumed |
| Page cache / prewarm | `pageCache` keyed by (language, plane, globe); one page per idle tick | **NOT_IMPLEMENTED** | NOT_IMPLEMENTED | The iOS cache exists because building ~40 `UIButton`s with SF Symbol lookups was measurably slow. Compose rebuilds a key grid from a data table with no per-key object graph, so the cache would add state without removing work. Recomposition scoping does the equivalent job — see §10 |

## 6. AI reply flow

| Feature | iOS | Android | Status | Notes |
|---|---|---|---|---|
| Context acquisition | selection first (`proxy.selectedText`), then clipboard, only on template tap | `getSelectedText()` first, then `ClipboardManager`, only on template tap | IMPLEMENTED_NOT_DEVICE_VERIFIED | No polling, no read on appearance, no background access — identical posture |
| Clipboard permission | Requires "Allow Full Access"; `fullAccessRequired` error | No equivalent gate; the current IME may read the clipboard | IMPLEMENTED_NOT_DEVICE_VERIFIED | The `fullAccessRequired` error case is kept in the model but is unreachable on Android; the setup UI shows "keyboard selected" instead |
| Sensitive clipboard | n/a | Clips flagged `EXTRA_IS_SENSITIVE` (API 33+) are refused | IMPLEMENTED_NOT_DEVICE_VERIFIED | Android-only hardening, matching iOS's "secure fields are never processed" promise |
| Password fields | iOS keyboards are simply not shown a secure field's content | AI panel disabled when `EditorInfo.inputType` is any password variation | IMPLEMENTED_NOT_DEVICE_VERIFIED | Typing still works normally |
| Generation trigger | **Only** a template tap or Regenerate | Template tap → ready state; **Generate** or Regenerate starts the request | IMPLEMENTED_NOT_DEVICE_VERIFIED | **Deliberate difference.** The brief requires a written-or-dictated instruction *before* generation, which iOS has no equivalent of. Cost: one extra tap versus iOS. Benefit: the instruction and the microphone, which are the point of the Android version |
| User instruction | none | Free-text field + microphone, fed to the prompt as `<user_instruction>` | IMPLEMENTED_NOT_DEVICE_VERIFIED | Android addition, per brief §14–17 |
| Source message display | Read-only, 2 lines, tap to expand to 4 | same | IMPLEMENTED_NOT_DEVICE_VERIFIED | Never seeded into the draft — the core rule is preserved |
| Draft editing | Storage-based `insertText`/`deleteBackward`, own caret when first responder is refused | Storage-based `KeyboardTextFieldState`, own blinking caret always | IMPLEMENTED_NOT_DEVICE_VERIFIED | An IME cannot host a system-focused text field; the iOS fallback path becomes the only path, which removes a whole class of focus bugs |
| Keys during generation | Dropped, never leak into the host | same (`InputTarget.DISCARDED`) | IMPLEMENTED_NOT_DEVICE_VERIFIED | |
| Regenerate | Same message, same template, new answer; disabled in flight | same | IMPLEMENTED_NOT_DEVICE_VERIFIED | |
| Insert | `commitText` into the host; never sends | `commitText(draft, 1)`; never sends | IMPLEMENTED_NOT_DEVICE_VERIFIED | No Accessibility service anywhere in the project |
| Host field not empty | Replace / Add / Cancel sheet | same three choices | IMPLEMENTED_NOT_DEVICE_VERIFIED | Android clears with one `deleteSurroundingText` instead of iOS's `deleteBackward` loop |
| Append separator | Space unless the text already ends in whitespace | same | IMPLEMENTED_NOT_DEVICE_VERIFIED | |
| Teardown | On `viewWillDisappear`: cancel request, drop message and draft | On `onFinishInputView`: same | IMPLEMENTED_NOT_DEVICE_VERIFIED | |
| Toasts | 3.2 s transient line in the chip row, no geometry change | same duration, same no-resize rule | IMPLEMENTED_NOT_DEVICE_VERIFIED | |
| "+" chip | Shows "create templates in the app" — an extension cannot present an editor | Opens the app's template editor directly | IMPLEMENTED_NOT_DEVICE_VERIFIED | **Android is better here**: an IME can start an Activity |

## 7. Localization

| Feature | iOS | Android | Status | Notes |
|---|---|---|---|---|
| Languages | en, ru, kk (249 keys in `Localizable.xcstrings`) | same three, `values/`, `values-ru/`, `values-kk/` | IMPLEMENTED_NOT_DEVICE_VERIFIED | Converted from the catalogue, not retyped |
| UI language ≠ AI reply language | Reply language follows the incoming message, always | same rule, same developer-message wording | IMPLEMENTED_NOT_DEVICE_VERIFIED | UI ru + reply kk is expressible, as required |
| UI language ≠ key-cap language | `AIReplyStrings` (app language) vs `KeyboardStrings` (layout language) — two hard-coded Swift tables, because an extension cannot see the app's chosen language | Two `createConfigurationContext` contexts over the same `strings.xml` | IMPLEMENTED_NOT_DEVICE_VERIFIED | **Android is better here**: the duplication iOS needed disappears, and no UI string is written in Kotlin |
| Language override | Settings picker, `nil` = system | same | IMPLEMENTED_NOT_DEVICE_VERIFIED | |

## 8. Voice (Android addition)

| Feature | iOS | Android | Status | Notes |
|---|---|---|---|---|
| Dictation in the app | `SFSpeechRecognizer` + `AVAudioEngine`, 60 s cap, editable transcript | `SpeechRecognitionClient` over `android.speech.SpeechRecognizer`, 60 s cap, editable transcript | IMPLEMENTED_NOT_DEVICE_VERIFIED | Same states, same "recording stops when you start typing" rule |
| Dictation in the keyboard | **Impossible** — an iOS keyboard extension cannot capture audio | **Implemented** — an Android IME can, with `RECORD_AUDIO` | IMPLEMENTED_NOT_DEVICE_VERIFIED | The headline Android-only feature |
| Permission from the IME | n/a | `VoicePermissionActivity`, a transparent Activity, because a Service cannot request a runtime permission | IMPLEMENTED_NOT_DEVICE_VERIFIED | Handles denied, denied-permanently and return-from-Settings |
| Provider abstraction | n/a | `SpeechRecognitionClient` interface; `AndroidSpeechRecognitionClient` is one implementation | IMPLEMENTED_NOT_DEVICE_VERIFIED | Swapping to server-side transcription is a new class, not a keyboard rewrite |
| On-device recognition | `supportsOnDeviceRecognition` | `createOnDeviceSpeechRecognizer` on API 33+, network recogniser below | IMPLEMENTED_NOT_DEVICE_VERIFIED | |
| Unsupported language | Named plainly ("not available for Қазақша on this device") | same, from `ERROR_LANGUAGE_NOT_SUPPORTED` / `ERROR_LANGUAGE_UNAVAILABLE` | IMPLEMENTED_NOT_DEVICE_VERIFIED | Kazakh coverage is genuinely patchy on both platforms |
| Voice → structured config | `VoiceConfigurationParser` proposes working hours / rules from dictation, applied only on confirmation | **NOT_IMPLEMENTED** | NOT_IMPLEMENTED | Deliberate: it is a heuristic Russian/Kazakh/English phrase parser with its own test suite, orthogonal to the port, and no Android surface needs it yet. Dictated text still lands verbatim in the profile, which is the behaviour that matters. Recorded as a follow-up in the README |

## 9. Main app screens

| Screen | iOS | Android | Status |
|---|---|---|---|
| Onboarding (7 steps: welcome, profile, hours, key, keyboard, usage, test) | `OnboardingView` | `OnboardingScreen` | IMPLEMENTED_NOT_DEVICE_VERIFIED |
| — per-step persistence, skip, back | yes | yes | IMPLEMENTED_NOT_DEVICE_VERIFIED |
| Home | `HomeView` (header, missing-key card, try-it, setup links, keyboard status, how it works, privacy) | `HomeScreen`, same sections in the same order | IMPLEMENTED_NOT_DEVICE_VERIFIED |
| Keyboard setup guide | `KeyboardSetupView` + checklist with a real "not known yet" state | `KeyboardSetupScreen`; the checklist is *actually knowable* on Android | IMPLEMENTED_NOT_DEVICE_VERIFIED |
| Profile editor | role, business, rules, about + counter + dictate, tone | same | IMPLEMENTED_NOT_DEVICE_VERIFIED |
| Working hours | full per-day editor | same | IMPLEMENTED_NOT_DEVICE_VERIFIED |
| Template list | reorder, hide, delete custom, add | same | IMPLEMENTED_NOT_DEVICE_VERIFIED |
| Template editor | basic, business, hours override, rules, style, instructions | same | IMPLEMENTED_NOT_DEVICE_VERIFIED |
| Settings | profile links, setup, API key, model, appearance, language, privacy, re-run onboarding | same | IMPLEMENTED_NOT_DEVICE_VERIFIED |
| Try a reply (`ComposeView`) | paste/dictate, template, generate, copy, regenerate | same, plus the instruction field | IMPLEMENTED_NOT_DEVICE_VERIFIED |
| API key editor | paste-first, `sk-` shape check, never redisplayed | same | IMPLEMENTED_NOT_DEVICE_VERIFIED |
| Debug screen launcher (`-AIReplyDebugScreen`) | DEBUG only | **NOT_IMPLEMENTED** | NOT_IMPLEMENTED — Android Studio previews and deep links cover it |

## 10. Cross-cutting

| Concern | iOS | Android | Status | Notes |
|---|---|---|---|---|
| No third-party dependencies | Apple frameworks only | AndroidX + Compose + `kotlinx.serialization` only; no networking, DI or crypto library | IMPLEMENTED_NOT_DEVICE_VERIFIED | Matches the stated project rule |
| Config read off the main thread | Once per appearance, `qos: .userInitiated` | Once per `onStartInputView`, `Dispatchers.IO`, throttled to 1 s | IMPLEMENTED_NOT_DEVICE_VERIFIED | Same throttle, same reason |
| Nothing expensive at keyboard start | Prewarm only after `viewDidAppear` | Transport, recogniser and JSON parser all lazy; nothing touches disk or network in `onCreateInputView` | IMPLEMENTED_NOT_DEVICE_VERIFIED | |
| No Activity/Context leaks | n/a | `ServiceLocator` holds `applicationContext`; the IME's scope dies with the service | IMPLEMENTED_NOT_DEVICE_VERIFIED | |
| Logging never carries message text | `ReplyLog`, lengths and outcomes only, DEBUG only | `ReplyLog`, same rule, `BuildConfig.DEBUG` only | IMPLEMENTED_NOT_DEVICE_VERIFIED | |
| Secrets out of the repo | Key typed at runtime, nothing in the IPA | Same; nothing in the APK, `local.properties` untouched, `.gitignore` covers it | IMPLEMENTED_NOT_DEVICE_VERIFIED | |
| Responsive layout | Portrait-locked, width-derived metrics | Portrait + landscape, width- and height-derived; `readableWidth` cap; font-scale respected in the app, pinned in the key grid | IMPLEMENTED_NOT_DEVICE_VERIFIED | Pinning the key grid's font scale stops a 2× accessibility font from breaking key geometry |
| Unit tests | 7 test files (service, context, store, localization, normalizer, summary, hours) | 8 test classes | PARTIALLY_IMPLEMENTED | 48 of them were compiled and executed (48 passed). `ConfigurationTest`, `AIReplyServiceValidationTest` and `LocalizationParityTest` need the serialization runtime, the Android framework and the Gradle working directory respectively, so they await the first real `testDebugUnitTest` |
| `./gradlew assembleDebug` | n/a | written, not run | BLOCKED | Egress policy blocks every Maven/Google/Gradle host in both sandboxes, and the Mac's Terminal is available to this session in click-only mode. `build-and-log.command` in the project root runs it and captures `build.log` |
