# Native read-along — design

_2026-09-07. Approved by the owner in conversation ("I want what ElevenReader does, beautiful text
UI … they don't display a page"; "I want theme app wide"). Amends the main spec
(`2026-09-01-t2s-reader-design.md`) §2.4.5 Reader page, §2.4.2, §6.1 — recorded there as rev 11 when
Plan 10 lands._

## 1. Why

The Reader page hands the book's HTML to Readium's web view. Even with publisher styles off, what
appears is the publisher's structure — a centred uppercase title, first-line indents, footnote marks,
link colours from Readium's stylesheet — on a page whose theme is a Reader-only preference that
nothing else in the app follows. With that preference on Dark and the phone in light mode the page is
black under light chrome (reproduced in the simulator on 2026-09-07). The owner's verdict: it looks
like pages from a PDF, not like our UI.

ElevenReader, the reference, never shows the document's layout. It pulls the text out and draws it
itself: one font, left aligned, a blank line between paragraphs, headings as bold text in the flow,
the paragraph being read tinted and the spoken word tinted darker, the way podcast and music apps
show transcripts and lyrics. That is what this design builds. The timeline the app already
synthesizes from is the text; the Reader stops needing Readium at all.

## 2. What the page shows

Unchanged from Plan 9: the floating top circles, the `Back to current` pill, the bottom block
(thin scrubber, times, transport row, tool row) and the `ground` fades the text scrolls under.

The body becomes one continuous column of our own text on `ground`, `Spacing.margin` (24 pt) from
each edge, scrolling from the document's first word to its last:

- **Document title** at the top in the Page title role (Inter Display Black 34), then a byline in
  the Meta role and `ink2` when the document has an author. Nothing else above the text — the
  first line starts under the top circles' band (content inset 96 pt from the safe-area top), the
  last line ends above the bottom block (inset 240 pt).
- **Chapter titles** in the Player title role (Inter Display ExtraBold 26), 40 pt above, 16 pt
  below. A chapter's own first block, when it says the same thing as its contents title, *is* the
  chapter title and is styled as one (and tinted while it is read); otherwise the contents title
  is drawn above the chapter's first paragraph as text that is never spoken. A chapter title that
  repeats the document title is not drawn.
- **Headings** inside a chapter in Inter SemiBold: 1.15 × the body size for h1–h3, the body size
  for h4–h6; 24 pt above, 8 pt below.
- **Body** in Inter Regular at 18 pt × the reader's text scale, line height multiple = the
  reader's line height (1.5 default), normal tracking, natural alignment, no hyphenation, no
  first-line indent, a paragraph gap of 0.75 × the body size. Text is `ink`; nothing on the page
  uses another hue except the two tints.
- **Tints.** The paragraph under the playhead is tinted `accentFaint`; the word being spoken is
  tinted `accentSoft` on top of it. Both are rounded (4 pt) rectangles drawn per line behind the
  glyphs, hugging the text of each line, so a paragraph reads as a soft block and a word as a
  pill. On a PDF a page has no paragraphs, so the tinted unit there is the utterance (two or three
  sentences), and the word tint is unchanged.
- **Following.** A word change scrolls so the word sits in the middle third of the visible area,
  animated, and only if it is outside that third. A drag by the reader suspends following (the
  pill appears); `Back to current` re-centres the word and resumes. Opening the page lands on the
  active word without animation.
- **Taps.** A tap on a word seeks to that word (its timing inside its utterance, exactly as Plan 9's
  taps did). A tap on text that is not spoken (a drawn contents title, the byline) or beside the
  text toggles the chrome, as today.
- **Live settings.** Text size and line height from the Appearance sheet re-style the text in
  place and keep the active word where it was on screen. Theme is app-wide (§6).

## 3. The text model — `ReaderText` (T2SApp, pure, tested)

`ReaderText(documentID:timeline:title:author:)` turns a `Timeline` into a list of paragraphs and
one flattened string, and answers the three questions the view asks. It has no UIKit in it. The
`documentID` is its identity: the view rebuilds its attributed text only when the id or a text
setting changes, never on the ticks that redraw the highlight.

**Paragraph.** `id` (its index), `kind` (`documentTitle`, `byline`, `chapterTitle`,
`heading(level)`, `body`), `chapterIndex` (nil for the title and byline), `text`, `location` (the
paragraph's UTF-16 offset in the flattened string), `spans` (the utterances it holds, in order,
each with its `utteranceIndex` and its UTF-16 `range` inside `text`; empty for text that is never
spoken), and `tintsWholeParagraph` (false for PDF pages).

**Grouping.** Consecutive utterances of one chapter belong to one paragraph while they share
`position.resourceHref` and `position.cssSelector`. When `cssSelector` is nil (PDF) the key is
`resourceHref` + `progression` — one paragraph per page — and `tintsWholeParagraph` is false.
A paragraph's `text` is its utterances' `source` strings joined by one space; `spans` record where
each landed. Every whitespace character inside a source (newlines from PDF lines, tabs) is shown
as a space; the length never changes, so offsets into `source` and into `text` are the same
numbers shifted by the span's start. (Readium already collapses runs of whitespace inside a block,
and the PDF reader joins lines with single newlines, so no gaps appear.)

**Headings.** A block whose `cssSelector` ends in an element `h1`…`h6` (the tag name at the start
of the selector's last `>` segment, before any `.`, `#`, `:` or `[`) is a `heading(level:)`.
Selectors that end in an `#id` say nothing about the tag, so those blocks stay body — an accepted
limit; Readium 3.11 labels every text element `.body` and offers no better signal.

**Chapter titles.** For each chapter: normalize the chapter's title and its first paragraph's text
(collapse whitespace, case-fold, strip trailing `.:;`); when they are equal, that first paragraph's
kind becomes `chapterTitle`; when they differ, a `chapterTitle` paragraph with the contents title
and no spans is inserted before it. No chapter title is inserted when the normalized title equals
the normalized document title (single-chapter articles).

**Flattened string.** Paragraph texts joined by `"\n"`, in order; `location` of each paragraph is
its start in that string. `ReaderText.length` is the total.

**Queries** (all UTF-16, all in flattened-string coordinates):

- `paragraphIndex(forUtterance:)`.
- `wordRange(for: HighlightRange) -> Range<Int>?` — the highlight's `sourceRange` shifted into the
  document.
- `tintRange(forUtterance:) -> Range<Int>?` — the whole paragraph, or the utterance's own range on
  a PDF page.
- `hit(at documentOffset: Int) -> (utteranceIndex: Int, sourceOffset: Int)?` — the utterance whose
  span contains the offset, with the offset inside its `source`; an offset in the gap between two
  spans of the same paragraph maps to the next span at source offset 0; nil for an offset in a
  paragraph with no spans or past the end.

**Cost.** Linear in the timeline, built once per document off the main thread; a 24-hour book is
roughly 1.2 million UTF-16 units and a few thousand paragraphs.

## 4. The view — `ReaderTextView` (App, UIKit hosted in SwiftUI)

A `UIViewRepresentable` wrapping one non-editable, non-selectable `UITextView` that shows the whole
document, backed by TextKit 2. The representable takes plain values — the `ReaderText`, `textScale`,
`lineHeight`, the active `HighlightRange?`, `isFollowing` — plus two callbacks (`onTap`,
`onUserScroll`), and a small `Coordinator` owns the UIKit state. Nothing in it reads an
`@Observable` object: SwiftUI re-runs `updateUIView` whenever one of those values changes, which is
what the Appearance sheet needs to work live.

**Attributed text.** Built from `ReaderText` and the two settings by a pure function
(`ReaderTypesetter.attributedString(for:scale:lineHeight:)`), on a background task, then assigned on
the main actor. Fonts by name from the bundled faces (Inter-Regular, Inter-SemiBold,
InterDisplay-ExtraBold, InterDisplay-Black); paragraph styles carry the line-height multiple,
spacing before/after, and alignment. Every run carries the dynamic `ink` as its foreground colour
and the byline `ink2` (UIKit's `textColor` applies to the whole string and would flatten the
byline); the colours are dynamic `UIColor`s, so a theme change recolours without a rebuild —
verified in the dark screenshots. A superseded typeset stops at the next paragraph boundary (the
typesetter checks cancellation once per paragraph) and the coordinator cancels its build when it
goes away.

**Highlight overlay.** A `CALayer` under the text (a subview of the text view's container, behind
the text container's drawing) holding two `CAShapeLayer`s: paragraph tint, word tint. On each
highlight change the coordinator asks TextKit 2 for the segment rectangles of the two ranges
(`NSTextLayoutManager.enumerateTextSegments(in:type:.highlight)`, after `ensureLayout(for:)`),
offsets them by the text container inset, unions consecutive line rects into rounded paths (4 pt)
and swaps the layers' paths. No attribute changes, no re-layout, per word. Neither layer is
drawn when there is no highlight.

**Taps.** A `UITapGestureRecognizer` on the text view. The coordinator maps the point to a
character with TextKit 2 (`textLayoutFragment(for:)`, then the line fragment containing the point,
then `characterIndex(for:)`); a tap counts as on text when the point lies inside that line's
typographic bounds widened by 8 pt. On text → `ReaderText.hit(at:)` → `onTap(.word(utteranceIndex,
sourceOffset))`; anywhere else → `onTap(.elsewhere)`. `layoutManager` (TextKit 1) is never
touched: reading it silently downgrades the view.

**Following.** On a word change while `isFollowing`, compute the word's rect; if its centre is
outside the middle third of the visible area (the frame minus the two insets), animate the content
offset so the centre lands mid-screen, clamped to the content bounds. `scrollViewWillBeginDragging`
calls `onUserScroll`, which suspends following in `ReaderModel`; programmatic scrolls do not go
through that delegate, so no time window is needed. When `isFollowing` flips back to true the
coordinator re-centres at once. On first layout with content the active word is centred without
animation, and once more on the next run-loop turn, because TextKit 2 estimates the height of
text it has not laid out and the first answer can be off. The first centre after content arrives
is never animated even when the first highlight lands later than that layout (audio is still
rendering at open, the common case); every centre after that first one animates.

**Settings changes.** A new scale or line height rebuilds the attributed string; the coordinator
remembers the active word's document range, assigns the new text, and re-centres that word without
animation.

**Insets.** `textContainerInset = (96, 24, 240, 24)`, `lineFragmentPadding = 0`, the scroll
indicator inset to match the bottom block. The top figure is measured from the safe-area top,
not from the view's own top — the view ignores only the bottom safe area — so 96 pt is what
clears the 150 pt top band of circles and fade; the original 72 assumed a view that also ignored
the top safe area. Background clear (`ground` comes from the page).

## 5. The page, and what goes

`ReaderPage` keeps its layout and sheets. `open()` no longer opens a Readium publication: after
`player.load`, it builds `ReaderText` from the coordinator's timeline (off the main actor) and
shows `ReaderTextView` for every source type — EPUB, article, PDF. The word-level read-along now
also applies to PDFs, as their text is drawn like anything else; the main spec's §6.1 caveat is
retired and replaced by: "PDF read-along shows the extracted text, not the page image; running
headers and footers are filtered at import (§4.1)."

Removed: `EPUBReaderView`, `PDFReaderView`, `ReaderScripts`, `PublicationCache`, `ReaderError`,
`AppEnvironment.publications`, and the app's links to `ReadiumNavigator` and
`ReadiumAdapterGCDWebServer` in `App/project.yml`. `T2SReadium` (import, positions,
`LocatorMapping`) is untouched.

`ReaderModel` gains `seek(toUtterance:sourceOffset:)`, built on the timing lookup that Plan 9 wrote
for taps, now taking the utterance directly instead of text-matching a block. The tap-matching
path — `SourceHit`, `seek(to:)`, `utteranceIndex(for:in:)`, `rawOffset(forCollapsed:in:)`, the
page-count recovery — and `activeSentence` with `Highlighter.sentence` are deleted with their
tests once the new view is verified in the simulator.

## 6. Theme, app-wide

An app-target extension gives `ReaderTheme` a `colorScheme: ColorScheme?` (`system` → nil; the
`T2SApp` package stays free of SwiftUI). The root pager and the Reader page (a full-screen cover,
its own presentation) apply `.preferredColorScheme(preferences.theme.colorScheme)`, so every
screen, every sheet and the Reader's UIKit text view (through the window's trait collection)
follow the choice together. The Appearance sheet and the Preferences page keep their Theme control; its caption
says it applies to the whole app. The Reader-only theme path in the old web view goes with it.

## 7. Errors and edges

- A timeline with no utterances shows the message only ("This document has no readable text."),
  not the title.
- A highlight whose utterance is not in the text (the playhead past the end) draws no tint.
- Word timings absent (an utterance not yet rendered): the Highlighter's estimated word still
  maps to a range, so the tint follows the estimate as it does now.
- The timeline object changes as rendering fills in audio (`timelineRevision`); the text does
  not, so `ReaderText` is built once per document and not rebuilt on revision changes. A
  destructive change that reloads the document (voice change) reopens the page's text.
- Very long documents: the attributed string is built off the main actor; assignment and TextKit
  2's lazy layout keep the page responsive. If a device ever proves otherwise, chapter-at-a-time
  loading is the fallback and needs no model change.

## 8. Testing

- `ReaderTextTests` (swift-testing, `Tests/T2SAppTests`): grouping by block; a PDF page as one
  paragraph with utterance-level tints; heading levels from selectors, `#id` selectors staying
  body; the chapter-title merge rule in both directions and the document-title exclusion; the
  byline; `location`s and `length`; `wordRange`, `tintRange`, `hit(at:)` including gap and
  never-spoken cases; whitespace shown as spaces without changing lengths.
- `ReaderModelTests`: `playhead(utteranceIndex:sourceOffset:in:)` — the existing word-timing
  cases rewritten against the new entry point; `seek(toUtterance:sourceOffset:)` resumes following.
- The UIKit view has no unit tests (the app target has none). Verification is silent simulator
  screenshots — `SIMCTL_CHILD_T2S_SILENT=1` — in light and dark and at text scale 1.6, checked
  against §2, and the owner's phone for taps and scrolling, which the Mac cannot drive.

## 9. Out of scope

Images, tables and footnote text (they are not spoken and are not drawn); text selection,
notes and sharing a quote; a chapter-at-a-time loader; per-paragraph "play from here" buttons;
removing `LocatorMapping`'s highlight half from `T2SReadium` (nothing calls it after this, but its
tests run only on the simulator and the package is left alone).
