# AI Reply — Android

A native Kotlin port of the AI Reply iOS app: a messaging keyboard that writes
the reply for you. You copy a message in WhatsApp, Telegram, Instagram or
anywhere else, switch to the AI Reply keyboard, say who you are replying to and
what you want to say, and it drafts the message. You edit it, insert it, and
send it yourself.

The iOS project at `../AI-Reply` is the source of truth for everything the
product does. This one adds a microphone.

---

## What it is

Two things in one APK:

* **The app** — onboarding, your profile, reply templates, working hours,
  settings, and a "Try a reply" screen for checking that your setup produces the
  replies you expect.
* **The keyboard** — a full three-layout keyboard (English, Русский, Қазақша)
  with an AI reply panel above the keys.

### The reply flow

```
you copy a message          →  long press, Copy, in any chat app
switch to the AI keyboard   →  the copied text appears as context
tap who it is from          →  Friend · Client · Business · Work · your own
say what to write           →  type it, or hold the microphone and say it
Generate                    →  the model drafts the reply
edit it                     →  it is your message now, not the model's
Insert                      →  it goes into the field you were typing in
```

Nothing is ever sent for you. The messenger's own Send button stays under your
finger, and this project contains no accessibility service that could press it.

### What is different from iOS

| | iOS | Android |
|---|---|---|
| Dictating an instruction **inside the keyboard** | impossible — a keyboard extension cannot capture audio | **yes**, this is the headline addition |
| Knowing whether the keyboard is enabled | no API; the keyboard writes a timestamp and the app infers | Android answers directly, so the setup checklist is a fact |
| Opening the keyboard settings | can only open the app's own settings page | a public intent lands exactly where the user needs to be |
| The "+" chip in the keyboard | shows a hint, because an extension cannot present an editor | opens the template editor |
| Two string tables for two languages | two hand-written Swift tables | one `strings.xml`, read through a locale-configured `Context` |
| Generating | tapping a chip generates immediately | tapping a chip opens the instruction field; **Generate** starts it |

The last row is the one deliberate regression: one extra tap, in exchange for the
instruction field and the microphone. `docs/IOS_ANDROID_PARITY.md` records every
difference, with reasons.

---

## Build

### Requirements

| | |
|---|---|
| Android Studio | Ladybug (2024.2) or newer |
| JDK | 17 (Android Studio's bundled JBR is fine) |
| Android SDK | API 35 platform, build-tools 35.0.0 |
| Gradle | 8.11.1, via the checked-in wrapper |
| AGP / Kotlin | 8.7.3 / 2.0.21 |
| Minimum device | Android 8.0 (API 26) |

Versions are pinned in `gradle/libs.versions.toml`. They are a combination known
to work together rather than the newest of each — see *Known limitations*.
Android Studio will offer to upgrade AGP and Kotlin; taking that offer is safe
as long as the Compose BOM and the Compose compiler plugin move with Kotlin.

### Android Studio

1. **File ▸ Open**, choose this folder, and let it sync. Studio writes
   `local.properties` with your SDK path on first sync; that file is
   git-ignored and must not be committed.
2. Run the `app` configuration on a device or emulator (API 26+).

### Command line

```bash
./gradlew assembleDebug           # debug APK → app/build/outputs/apk/debug/
./gradlew testDebugUnitTest       # unit tests
./gradlew lintDebug               # Android Lint
./gradlew assembleRelease         # needs a signing config; none is checked in
```

If `local.properties` is missing:

```bash
echo "sdk.dir=$HOME/Library/Android/sdk" > local.properties
```

`build-and-log.command` does all of the above and writes `build.log`.

---

## Setting the keyboard up

1. Open AI Reply and go through onboarding (or Settings ▸ Keyboard setup).
2. Tap **Open keyboard settings** — this lands on the system's on-screen
   keyboard list. Turn **AI Reply** on. Android will warn you that a keyboard
   can see what you type; that warning is shown for every third-party keyboard.
3. Tap **Switch keyboard** and pick AI Reply, or use the keyboard button in the
   navigation bar.
4. The checklist on the setup screen turns green as each step completes. It is
   read from the system, not guessed.

### AI configuration

The app ships with no credentials and contains none.

* **Settings ▸ OpenAI ▸ API key** — paste a key beginning with `sk-`. It is
  encrypted with an AES-256/GCM key held in the Android Keystore and stored in
  an app-private file that is excluded from cloud backup and device transfer.
  It is never logged, never shown again, and never leaves the device except in
  the `Authorization` header of a request you asked for.
* **Settings ▸ Model** — `gpt-4o-mini` by default.

This is the *direct* mode, and it is a development mode. A key that reaches a
device is a key the device's owner can extract, and every request is billed to
it with no rate limit but the provider's own. `BackendTransport` is the
production shape, where the key never reaches a device at all;
`docs/AI_REPLY_PLATFORM_ARCHITECTURE.md` is the plan for getting there.

### Voice

The microphone is requested the first time you tap it, never on launch. An input
method cannot show a permission dialog itself, so tapping the microphone briefly
opens a transparent activity that asks on its behalf and closes again.

Recognition uses Android's on-device recogniser where the device has one
(API 33+), and the networked one otherwise. Kazakh coverage is patchy on both;
when a language has no model the keyboard says so rather than leaving you
holding a button that can never produce text.

### Languages

The app, the keyboard's product labels, and the key captions are three separate
questions:

* **App language** — Settings ▸ Language, or the system default. Drives the
  screens, the template chips, Insert, Regenerate and every error message.
* **Keyboard layout** — the `EN`/`РУ`/`ҚАЗ` key cycles it. Drives the character
  keys and the space/return captions only.
* **Reply language** — follows the incoming message, always. Russian in, Russian
  out. It is never the app's language, so a Kazakh interface can produce a
  Russian reply to a Russian message.

---

## Project structure

```
app/src/main/java/kz/yerek/aireply/
├── AIReplyApplication.kt      the object graph, built once for app and keyboard
├── ServiceLocator.kt          manual DI — no framework on the keyboard's path
├── MainActivity.kt            the only Activity
│
├── core/lang/                 AppLanguage, KeyboardLanguage, LocalizedContext
├── core/text/                 code-point-accurate length limits
│
├── domain/model/              UserProfile, BusinessContext, ReplyTemplate,
│                              WorkingHours, ReplyConfiguration — pure values
│
├── data/settings/             SharedPreferences, readable synchronously
├── data/profile/              the JSON configuration file + its observable view
├── data/secure/               Android Keystore credential storage
│
├── ai/                        AIReplyService, ReplyPromptBuilder, the two
│                              transports, the closed error set
│
├── keyboard/                  ReplyKeyboardService (the IME), theme, metrics
│   ├── input/                 clipboard, host field, local text fields, status
│   ├── reply/                 the copy → instruction → AI → insert state machine
│   └── ui/                    the key grid and the reply panel, in Compose
│
├── voice/                     SpeechRecognitionClient + the Android one
├── platform/                  logging that never carries message text
└── ui/                        design system, navigation, and the app screens
```

Layer rules, in one line each:

* `domain` knows about nothing. `data` knows `domain`. `ai` knows `domain` and
  `data`. `keyboard` and `ui` know everything below them and nothing about each
  other.
* `ui` never touches a transport, and `keyboard` never imports from `ui/feature`.
* Nothing outside `data/secure` reads the credential; nothing outside
  `keyboard/input/ContextTextProvider` reads the clipboard.

### Decisions worth knowing before changing things

**No Hilt.** Half of this app is an input method, started at the moment the user
has switched keyboards and is staring at a blank strip. A generated component
and a reflective entry point on that path, to construct seven objects, is not a
trade worth making.

**No OkHttp or Retrofit.** Two kinds of POST, no interceptors, no converters.
`HttpURLConnection` does it in forty lines, and every class not loaded is
keyboard startup time not spent.

**SharedPreferences, not DataStore.** The keyboard's first frame must be correct
synchronously, and the three values it needs to do that are a few hundred bytes.
DataStore's choices there are `runBlocking` on the main thread or a visible
one-frame swap of the whole chip row. Preferences load once and are an in-memory
map afterwards; `AIReplyApplication` warms them. Observers still get a `Flow`.

**A JSON file, not Room.** The whole configuration is a few kilobytes, written
when a settings screen closes and read when the keyboard appears. `ProfileStore`
skips parsing when the file's modification time has not changed, so a keyboard
that opens repeatedly inside one messenger session pays a `stat`.

**Hand-rolled Keystore crypto, not `androidx.security`.**
`EncryptedSharedPreferences` does exactly this, but the library has been stuck in
alpha, is now deprecated, and pulls Tink in. `SecureCredentialStore` is ~120
lines with no dependency and no upgrade risk.

**The reply panel never takes height from the keys.** The keyboard window grows
instead. This is the rule that keeps typing comfortable in every state, and the
layout in `KeyboardRoot` is arranged so breaking it would take effort.

**The key grid reads only `KeyGridState`.** Nothing in it changes while you type,
so a keystroke recomposes nothing. A generation in flight — spinner, partial
voice transcript, growing draft — touches only the panel. Callbacks handed to
the grid are `remember`ed so their identity is stable; a method reference there
would silently defeat the whole arrangement.

---

## Privacy

These are properties of the code, not intentions:

* The clipboard is read in exactly one function, which runs only when you tap a
  template. No polling, no timer, no read on appearance, no background access.
* Clips another app has flagged sensitive — a password manager entry, say — are
  refused outright.
* The AI panel is disabled entirely in password fields.
* The copied message, your instruction and the draft exist only in memory, only
  while the panel is open, and are dropped when the keyboard closes.
* `ReplyLog` records lengths and outcomes, never text, and only in debug builds.
* Requests carry the message, your profile and the selected template. They carry
  no device identifier, no contacts, no chat history, no location, no
  advertising ID, no device model and no OS version. The per-install identifier
  is a random UUID generated locally and discarded on uninstall.
* Working hours send a wall-clock time and two booleans. No timezone, no city,
  no coordinates.
* There is no accessibility service in this project, and no code that reads
  another app's screen. The only way a message becomes context is that you
  copied it.

---

## Tests

```bash
./gradlew testDebugUnitTest
```

Eight classes, covering: the 300-character rule and code-point counting, prompt
construction (including that user text never reaches the developer message),
working-hours derivation and weekday grouping, draft normalization with URLs
preserved, configuration repair and tolerant decoding of older files, the three
keyboard layouts, auto-shift, and **localization parity** — that every string
exists in all three languages with matching format specifiers, which is the
failure that is otherwise silent until a Kazakh user sees an English sentence.

---

## Known limitations

**No Gradle build has been run against this source tree.** The environment it
was written in refuses `dl.google.com`, `maven.google.com`, `repo1.maven.org`,
`plugins.gradle.org` and `services.gradle.org`, so neither the Android SDK nor
any AGP or Compose artifact could be fetched, in either available sandbox. What
*was* done instead:

* every one of the 86 Kotlin files was parsed with the real Kotlin 2.0.21
  compiler front end — 0 parse errors;
* the domain models, `ReplyPromptBuilder`, `WorkingHours`, `ReplyDraftNormalizer`,
  the layout tables and `AutoShift` were compiled and their **48 tests executed
  — all passing**;
* all 280 `R.string` references were checked against the 327 declared strings,
  along with package/directory agreement and duplicate type names.

That covers syntax and the logic-dense core. It does not cover Compose
composition, the Android framework surface, or anything AGP does. Expect the
first `assembleDebug` to surface ordinary compile errors — an import, a Compose
API signature — and treat the version pins as the most likely place to need a
nudge.

**Other gaps, deliberate:**

* `VoiceConfigurationParser` was not ported. On iOS it proposes working hours and
  rules from dictated speech, applied only on confirmation. It is a heuristic
  phrase parser with its own test suite, orthogonal to the port. Dictated text
  still lands verbatim in the profile, which is the behaviour that matters.
* Template reordering is up/down buttons rather than drag-and-drop. Compose has
  no built-in equivalent of `List` + `EditButton`, and a hand-rolled drag in a
  list this short would be more code than the rest of the screen and worse with
  a screen reader.
* Release signing is not configured, on purpose: a keystore in a repository is a
  shipped secret.
* The backend the production transport talks to does not exist yet. See
  `docs/AI_REPLY_PLATFORM_ARCHITECTURE.md`.

---

## Documentation

* `docs/IOS_ANDROID_PARITY.md` — every feature, its iOS implementation, its
  Android equivalent, and its status.
* `docs/AI_REPLY_PLATFORM_ARCHITECTURE.md` — the design for the production
  backend, admin panel, subscriptions, usage metering, payments and analytics.
  **Design only. None of it is implemented, and none of it should be started
  before Phase 2 of the roadmap in that document.**
