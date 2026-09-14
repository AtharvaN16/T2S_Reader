# Onboarding — design

**Date:** 2026-09-14
**Owner decisions:** recorded inline, from the brainstorming session of the same day.
**Status:** design agreed; implementation plan to follow.

## Why

The app opens on Home with an empty shelf and an Import pill. Nothing speaks until the reader
finds a link or a file, so the moment the app exists for — a voice reading while the words light
up — is behind a chore. Sound is the product; the first thing a reader meets should be a voice
reading a great sentence.

The references are the Queue podcast app (cover cards rising in depth parallax, an app that is
already full when onboarding ends, a paywall last with *Later* and *Restore*) and the ATC replay
app (one card settles out of the drifting field, the aha before any question, questions after).
The pattern behind both, from the onboarding survey the owner watched: sell the outcome rather
than list features, get to the aha fast, and make personalization show what it unlocked.

## Owner decisions

- **Sound on launch.** The clips start with the cards. No tap-to-listen, no tilt. (Raised once as a
  concern; the owner reaffirmed it.)
- **No payment, no auth.** The Pro screen is a mock-up that only continues. No StoreKit, no
  account, no gating anywhere. Pro features stay unlocked.
- **The sample books are content, not props.** Five public-domain EPUBs ship in the bundle; the one
  the reader chose is imported and opens in the Reader when the flow ends. (Assumed from the
  session's recommendation; the owner did not object.)
- **One question only, multi-select**, after the voice, never before. Its answer orders the
  benefits page and decides which import Home offers first.
- **The pricing model** the app will eventually use is a one-time Pro unlock with a free tier —
  discussed the same day and recorded here so the mock paywall reads that way. Nothing in this
  design wires it.

## What exists today

Established by reading, not assumed:

- `RootPager` is the root (`App/T2SReader/Root/RootPager.swift`): a three-page pager opening on
  Home, a launch `.task` that refreshes the library, and `fullScreenCover`s for the Import page and
  the Reader. A `T2S_OPEN=reader` debug route opens the Reader from a script.
- `ReaderPreferences` (`Sources/T2SApp/Preferences/ReaderPreferences.swift`) stores everything
  in `UserDefaults` under dotted keys; `defaultVoiceID` is `voice.default`. Reader papers are
  `ReaderPaper` (eight zen, eight pop); `readerPaper` is the preference.
- `ImportModel.importFiles(_:)` (`Sources/T2SApp/Import/ImportModel.swift`) imports EPUBs from
  URLs and calls `afterImport` with the summaries. The Collection and the Import page already
  open the Reader on the result through `pendingOpen` → `readerDocument`.
- `KokoroVoiceCatalog.voiceNames` lists the 28 voices; `personalities` carries a line per voice;
  `VoiceOption` carries `name`, `gender`, `group`. `Delivery.applied(to:)` turns a voice id into
  the routed one. `VoicePreviewModel` renders a sample line live — not used here, because the
  onboarding clips are pre-recorded.
- `Utterance.wordTimings: [WordTiming]?` is the read-along's word timing type. The Reader tints
  the spoken word `accentSoft` and the paragraph `accentFaint` (spec §2.4.5). The onboarding
  reuses the type and the tints, not `ReaderTextView`.
- `AudioSessionController` sets `.playback / .spokenAudio / .longFormAudio`; `AudioPlayer` plays
  PCM. The clips are short, so `AVAudioPlayer` on the same session is enough.
- `Cover` in `Design/Primitives.swift` draws a book from its `relativePath` or an `asset`, keeps
  each cover's own proportion within `0.55...0.8`, and already has three designed empty-state
  covers in `Assets.xcassets/EmptyCovers` — the visual language the five sample covers follow.
- `Pill` has `soft`, `selected`, `accent` styles. Sheets and the Import cover are
  `fullScreenCover`s; `appTheme()` at the root colours every presentation.
- The hosted "Heart · Cloud" voice stands in for any on-device voice until the warm-up finishes;
  `WarmUpLine` in the Reader explains the hand-off. A reader who picks Bella hears Heart for the
  first minute on a cold install. Accepted.

## The flow

One `fullScreenCover` over the pager, presented at launch when the completion flag is unset,
with a container view that owns the step and the audio. Five screens; the first two are one
continuous scene.

### 1. Covers (scene, beat one)

Black `ground`. Cards rise from below the screen in three depth layers:

| layer | scale | blur | speed | count |
| --- | --- | --- | --- | --- |
| far | 0.55 | 14 pt | slow | 3 |
| middle | 0.75 | 6 pt | medium | 3 |
| near | 1.0 | 0 | fast | the book being read |

All cards drift upward on one axis with a slight rotation (±6°) and horizontal offset per card,
seeded so the choreography is the same every launch. No motion sensing. Reduced Motion: the cards
fade in and out in place with no travel.

Sound starts with the first card. Five clips play back to back, one opening line per book, each
in a different voice, roughly 6–9 s each. As each clip begins, that book's card enters at the near
layer, sharp, and passes through the middle third of the screen while its line plays; the other
cards are the far and middle field. The ear and the eye land on the same book.

No controls but Skip, top-right, from the first frame. Skip ends the scene and jumps to the
question; the hero book is still imported at the end (decision below).

### 2. Voice (scene, beat two)

After the fifth clip the field dims to black and the hero card — the fifth book — settles top
centre at full size, sharp, the way the ATC app's red card does. Beneath it its opening lines fade
in, Reader body type, and the hero clip replays with each word tinted `accentSoft` as it is spoken
and the paragraph `accentFaint`, from the timings shipped beside the clip.

Along the bottom, five voice pills in a horizontal scroll: three female, two male, first names
only, the reader's current pill in `selected` style. Tap or swipe (a paged `ScrollView` with
`scrollTargetBehavior(.viewAligned)`) changes the voice: the line restarts in that voice's clip.
A caption above the pills reads *Swipe to try a voice*. The last pill is followed by nothing;
"more voices" is a Pro benefit two screens on.

**Continue** writes the pill's voice id (`Delivery.applied(to:)` is the player's job, not ours —
we store the bare id, as the picker does) to `defaultVoiceID`. The default pill is Heart, which is
also the app's default, so a reader who never touches the row changes nothing.

The five voices: `af_heart` (Heart), `af_bella` (Bella), `af_nicole` (Nicole), `am_michael`
(Michael), `am_fenrir` (Fenrir). Kokoro's female voices grade above its male ones; these are the
strongest set with two men in it.

### 3. One question

*What will you listen to?* Multi-select pills, full width, stacked, `soft` → `selected`:
**Books · Articles · PDFs · Notes**. Continue is enabled with any selection; Skip clears it.
Stored as `onboarding.intent`, an array of the raw values.

### 4. Three things for you

Three pages in a horizontal pager with a page indicator, one Pro benefit each, in the order the
answer sets:

| benefit | leads when the answer includes | demo |
| --- | --- | --- |
| **Make it yours** — reader papers and highlight themes | Books, Notes | the Reader's text block in a scripted state cycling three papers |
| **Take a whole book with you** — render every chapter ahead, listen with the screen off | Books, PDFs | the book sheet's chapter boxes filling in sequence |
| **Every voice, said your way** — all 28 voices and the pronunciation dictionary | Articles | the voice row from screen 2 scrolling past more names |

Default order with no answer: papers, whole book, voices. Each demo is a real view in a scripted
state, driven by a timer, not a video — it cannot drift from the app and costs nothing in bundle
size. Continue on the last page; Skip on every page.

### 5. Pro (mock)

Title **Pro**, line *Buy once. Keep it forever.* The three benefits as rows with the same glyphs
as the previous screen. One `accent` pill reading **Continue** — deliberately not a price, because
nothing is for sale yet and a price that does nothing is a lie in a screenshot. *Later* top-left
and *Restore* top-right, both continue. This screen is the first thing a real paywall replaces.

### Ending

On finishing or skipping from any screen:

1. Set `onboarding.completed`.
2. Import the hero EPUB through `ImportModel.importFiles([url])` from the bundle. If the reader
   skipped from the covers before choosing anything, the hero is still imported — the shelf must
   not be empty after onboarding.
3. Dismiss the cover; the pager's existing `pendingOpen` → `readerDocument` path opens the Reader
   on the imported book, playing, in the chosen voice. The cloud stand-in and `WarmUpLine` behave
   as on any first listen.

The Reader is entered exactly the way an import enters it today; no new path.

### Replay

Settings → **Show the welcome again** presents the same cover, without importing the hero a
second time if it is already on the shelf (matched by the bundled file's title).

## Assets

**Five books**, public domain in the United States, from Standard Ebooks, chosen for a first line
a listener recognises in three seconds:

| book | opening | clip voice |
| --- | --- | --- |
| Moby-Dick | "Call me Ishmael." | Michael |
| Pride and Prejudice | "It is a truth universally acknowledged…" | Bella |
| A Tale of Two Cities | "It was the best of times, it was the worst of times…" | Fenrir |
| The Great Gatsby | "In my younger and more vulnerable years…" | Nicole |
| Alice's Adventures in Wonderland (hero) | "Alice was beginning to get very tired of sitting by her sister on the bank…" | Heart |

Alice is the hero because the lines after its first are still good aloud, and because it is short
enough to be the book a reader actually finishes.

**Covers** are our own, in the style of the three `EmptyCovers` assets, set as each EPUB's cover
image so the shelf and the scene draw the same picture. No publisher art.

**Clips:** the five rising lines and the hero's lines in all five voices — nine files, since
Alice in Heart serves both. Rendered on the Mac with our own Kokoro Core ML engine, to files
only, never played there (the owner's Mac must stay silent). AAC in `.m4a`, 24 kHz mono, under
one megabyte for all nine. Beside each, a JSON of `[WordTiming]` from the same render. Rendered
with the app's own voices and nothing better, so the first real listen is not a step down.

**Bundle:** `App/Resources/Onboarding/` — the five EPUBs (Standard Ebooks compressed, ~1–3 MB
each), nine clips, nine timing files, a `manifest.json` naming each book, its file, its clip, its
voice and its line. A fetch script pins the Standard Ebooks URLs and hashes, like the fonts.
Licence register: Standard Ebooks releases are public domain in the US (CC0 for their own
contributions); one row in `docs/licenses.md`.

## Where it lives

- `Sources/T2SApp/Onboarding/` — the testable model:
  - `OnboardingModel` (`@Observable`, `@MainActor`): `step`, `chosenVoiceID`, `intent`,
    `benefitOrder`, `advance()`, `skip()`, `finish()`; writes `defaultVoiceID` and the two
    preference keys; asks a closure to import the hero.
  - `OnboardingManifest`: decodes `manifest.json`; the book, clip and timing records.
  - `BenefitOrdering`: the pure rule from intent to benefit order.
  - `OnboardingRecord`: `isCompleted(defaults:)`, `markCompleted(defaults:)`, `clear(defaults:)`,
    in the style of `KokoroWarmUpRecord`.
- `App/T2SReader/Onboarding/` — the views, one file per screen plus the container and the
  choreography:
  - `OnboardingCover` (container, step switch, Skip, the clip player)
  - `CoverField` (beat one), `VoiceChoice` (beat two), `IntentQuestion`, `BenefitPages` with
    three demo views, `ProMock`
  - `ClipPlayer`: `AVAudioPlayer` on the app's session; publishes the current time for the tint.
  - `ReadAlongLine`: the fading-in lines with the word tint from `[WordTiming]` and a time.
- `RootPager`: presents the cover when `OnboardingRecord.isCompleted` is false, after the library
  has loaded, and wires the hero import to `pendingOpen`.
- `PreferencesPage`: the *Show the welcome again* row.
- `ReaderPreferences`: no change; `onboarding.*` keys are the record's, not the preferences'.

## Testing

Unit tests in `Tests/T2SAppTests/Onboarding/`:

- step order forward; skip from every step lands on finish; finish sets the record.
- the chosen voice is written to `defaultVoiceID`; no touch leaves it unchanged.
- `BenefitOrdering` for each single intent, for combinations, and for none.
- the manifest decodes the bundled file and every referenced file exists (a test that walks the
  resource bundle).
- the hero import closure is called exactly once, including on skip and on replay when the book
  is already on the shelf.

On the simulator: the existing silent screenshot recipe with `SIMCTL_CHILD_T2S_SILENT=1`, a debug
route `T2S_OPEN=onboarding` that clears the record on launch, and a photograph of each screen in
light and dark. The clips are not played in the recipe.

## Out of scope

Payment, accounts, notifications, any gating, an interactive tutorial inside the Reader, and the
share-sheet lesson (a later checklist on Home, not this flow).
