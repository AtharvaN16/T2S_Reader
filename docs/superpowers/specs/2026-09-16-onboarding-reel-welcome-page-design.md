# Onboarding — the reel, the welcome and the page

**Date:** 2026-09-16
**Supersedes:** beats one and two of `2026-09-14-onboarding-design.md`. Beats three to five of that
document (the question, the benefits page, the mock Pro screen) are untouched and still unbuilt.
**Status:** design agreed from the owner's brief of 2026-09-16; implementation follows in the same
session.

## Why

The welcome's first scene ends by picking a favourite. Alice's cover leaves the drift, climbs to
the top of the screen, grows, and the rest of the field dims away under it — the ATC replay app's
red card settling out of the crowd. The owner asked for that focus to go (2026-09-16: "let us
remove the focus on Alice in Wonderland"). What the scene sells is not one book. It is a shelf that
speaks, and then the app's name, and then what reading in it looks like.

So the scene stops being one continuous shot that resolves onto a hero, and becomes three, wiped
between rather than cut: the reel, the name, the page.

## The owner's brief, 2026-09-16

Recorded as given, because the beats below are only a reading of it:

- "Let the reel off all the books moving upward slowly continue as normal."
- "Then we will have a fade overlay move from bottom to the top revealing welcome to T2S."
- "After that the overlay will again shift to show a page with an excerpt from a book which can be
  Alice in Wonderland."
- A Mobbin screen as the reference for the covers: "See how it shows this skew, that's the way we
  need to proceed."
- "Then we can have the voice pills on the top of the screen, over a tall fade and there is a
  bottom fade."
- "The text moves between these two phases similarly to how it currently moves in the reader."
- "The top part will have like a glowing element which reacts to the voice … when switching
  between voices, the top element can show different types of glows."

### Assumptions, flagged

Two things in the brief this design had to decide rather than read off:

1. **The skew.** The linked Mobbin screen could not be opened — the Mobbin MCP searches by
   description and has no fetch-by-id, and the page itself answers 403 to an unauthenticated fetch.
   The nearest screen the search surfaced with a real skew is MD Vinyl's onboarding
   (`mobbin.com/screens/1cbd7282-83e7-48cd-b46a-43d8839aa023`): records laid back in perspective,
   leaning away from the reader, stacked up the screen like plates in a rack. That is the reading
   this design takes — a lean about the horizontal axis with a real perspective divide, not a 2D
   shear. `CoverField.tilt` is one number; if the reference meant something else, it is one number
   to change.
2. **No tap between the beats.** The brief describes the three beats as one run of motion, so the
   scene plays itself through and the Play key that used to stand between beat one and beat two is
   gone. Sound on launch was already the owner's decision (2026-09-14) and this only extends it.

## The flow

One scene, one wall clock, three beats. `Skip` sits top-right from the first frame to the last.

### 1. The reel

Every book in the manifest drifts upward in one field, as it does today: each cover has its own
depth, which sets its size, its speed, its blur and its dimness together, scattered across the
whole width with the edges cutting some off. The placing is still seeded from the index, so the
field is the same every launch, and the chatter still plays over it — a few opening lines, each
heard whole with the next fading into its tail (`ChatterSchedule`).

What is new is the **skew**. Each cover is laid back about its own horizontal axis under a
perspective divide, so it reads as a plane going away from the reader rather than a rectangle
sliding up the glass. The lean is not uniform: it grows with how high on the screen the cover has
climbed, so a cover enters near the foot almost square-on and is well laid back by the time it
leaves at the crown — the reel goes over a horizon. The old 2D roll stays, cut down, as the
little untidiness that keeps the field from looking machined.

What is gone is the hero: no cover leaves the drift, none grows, and the field never dims. Alice is
one book in the reel like any other.

### 2. The welcome

As the last line tails off, a **veil** rises from the foot of the screen to the crown: a sheet of
`ground` with a soft top edge — the app's own fade curve, `BottomFade.stops`, not a straight ramp —
that covers the reel from the bottom up as it climbs. *Welcome to T2S* is standing on that sheet
already, so the words are uncovered by the edge passing over them rather than faded in on top of
the covers. When the veil is home the screen is plain ground and the name.

It holds there for a beat, and the chatter is silent.

### 3. The page

The veil shifts again — a second rise, the same edge, the same curve — and what comes up under it
this time is the page: a passage from a book, read aloud, with the words lighting as they are
spoken. Alice's, because hers is the passage the manifest carries, but the page is about the
reading and not about the book.

Top to bottom:

- **The glow.** A bloom of coloured light at the crown of the screen, bleeding up through the
  status area. It has the selected voice's colour, and it breathes with the voice: brighter on a
  word, falling away between them. Each voice gets its own *form* as well as its own colour — an
  orb, a low wide band, two overlapping lobes, a ring, a tight core under a broad halo — cycled by
  the voice's place in the row, so a voice added to the manifest gets a form for nothing.
- **The pills**, over the glow's foot: one compact pill per voice in a horizontal row, the chosen
  one filled with its colour and the rest soft. A tap on another pill moves the passage to it; a
  tap on the chosen one plays it again once it has been heard through. A small caption beneath —
  *Swipe to try a voice* — because a row of first names does not say what it is for.
- **A tall top fade** under all of that, so the text dissolves beneath the pills instead of running
  into them.
- **The passage**, the Reader's own body type, everything up to the spoken word in `ink` and
  everything after it in `inkUnread` — the Reader's boundary, not a highlighter — scrolling itself
  so the spoken word stays in the middle. Exactly the motion the Reader has.
- **A tall bottom fade**, and **Continue** over it, which writes the chosen voice as the app's
  default and ends the welcome.

## Where the level comes from

The glow reacts to the voice without listening to it. `AVAudioPlayer`'s metering reports the
player's *output*, which `T2S_SILENT=1` pins at zero — the glow would be dead in every screenshot
the simulator recipe takes. The clips already ship with word timings beside them, so the level is
derived from those instead: a pure `VoiceEnvelope` over `OnboardingClipTimings` that attacks at
each word's onset and decays through it to a floor between words.

This is better than metering on three counts and worse on none that matter: it is silent-safe, it
is the same every run so a photograph is reproducible, and it is a plain function of time that can
be tested without an audio session.

## Where it lives

| file | what changes |
| --- | --- |
| `Sources/T2SApp/Onboarding/ChatterSchedule.swift` | loses the settle; `settleStart`/`settleLength`/`total` give way to `chatterEnd` |
| `Sources/T2SApp/Onboarding/WelcomeScript.swift` | new — the three beats' clock, built from the chatter's |
| `Sources/T2SApp/Onboarding/VoiceEnvelope.swift` | new — the glow's level, from the word timings |
| `App/T2SReader/Onboarding/CoverField.swift` | the hero and its settle deleted; the skew added |
| `App/T2SReader/Onboarding/RisingVeil.swift` | new — the wipe, used twice |
| `App/T2SReader/Onboarding/VoiceGlow.swift` | new — the bloom, a form and a colour per voice |
| `App/T2SReader/Onboarding/VoiceCarousel.swift` | the big boxes at the foot become compact pills at the crown |
| `App/T2SReader/Onboarding/OnboardingCover.swift` | three beats instead of two; the Play key deleted |

`OnboardingManifest.hero` keeps its meaning — the book whose passage beat three reads — and no
asset changes. Nothing outside `Onboarding/` is touched.

## Testing

The pure types carry the tests, as `ChatterSchedule` does today: `WelcomeScriptTests` for the beat
boundaries and the two sweeps' progress, `VoiceEnvelopeTests` for the attack, the decay and the
floor, and `ChatterScheduleTests` updated where the settle is gone. The views are checked by
type-checking against the simulator SDK and photographed on the private `T2S Onb` simulator, since
the full app build has a pre-existing `'Document' is ambiguous` failure unrelated to this work.

## What the photographs changed

Built, then photographed on the private `T2S Onb` simulator in both themes. Six things looked right
in the code and wrong on the glass; they are recorded here because each one is a rule about this
screen rather than a typo.

1. **A padded passage cuts; a full-bleed one dissolves.** Starting the text below the crown put its
   scroll view's hard edge in clear air under the caption. The passage runs the whole height and the
   two grounds cover its ends: it is cut where the ground is opaque and fades on the ramps.
2. **`scrollTo(anchor: .center)` cannot scroll above its own content start.** Without room at each
   end, the opening words stay pinned at the top — under the crown's fade, which is the one place
   the word being spoken must never be.
3. **A veil must overshoot.** Ending the travel with the ramp's foot on the crown leaves the last
   few points of screen under its clear end, and the beat underneath shows as a sliver.
4. **The pill's colour is not the glow's.** The pill's brightness is pitched for white text standing
   on it; laid over the near-white ground as a wash it is a brown stain, not light.
5. **An envelope's floor is most of every frame.** Mapped straight to opacity, the glow is at a
   fifth strength almost always. The level has to read as presence: the floor buys most of the
   brightness, the words buy the rest.
6. **The glow has to be masked to the crown.** It is drawn over the passage by necessity — the
   crown's solid ground is what hides the text — so unmasked it tints the first readable lines.

## Open questions for the owner

- **The rake, at 46°.** Records can be laid near-flat because a record is legible flat; a book laid
  that far back loses its cover art, and the topmost covers in the reel read as shapes rather than
  as books. `CoverField.tilt`.
- **The skew's reference.** Still the MD Vinyl reading, not the linked screen. See the assumption
  above.

## Out of scope

Beats three to five of the 2026-09-14 design. The Reader itself. The voice catalogue. Any change to
the clips, the manifest or the covers.
