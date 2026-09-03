# t2s_reader

An iOS app that turns EPUBs, web articles, and text PDFs into a read-along
audiobook experience, synthesized on-device. Design spec:
[docs/superpowers/specs/2026-09-01-t2s-reader-design.md](docs/superpowers/specs/2026-09-01-t2s-reader-design.md).

## Repository layout

```
Package.swift          Swift package "T2S". Targets: T2SCore (text pipeline), T2SAudio
                       (playback), T2SStore (SwiftData), T2SLibrary (ingest + library facade),
                       T2SApp (models, formatters).
Sources/<Target>/      library code, one directory per target
Tests/<Target>Tests/   Swift Testing suites; run with `swift test` on macOS
Packages/T2SReadium/   iOS-only package wrapping the Readium toolkit (EPUB reading, Locator
                       mapping). Readium does not build for macOS, so it is tested on the iOS
                       simulator with scripts/test-readium.sh.
App/                   the iOS app: project.yml → T2SReader.xcodeproj (generated, ignored),
                       T2SReader/ (SwiftUI views, composition root), Resources/Fonts (Inter, OFL)
scripts/               CI helpers (check-licenses.sh, test-readium.sh)
spikes/                throwaway experiments — never imported by shipping code
  SpikeHarness/        iOS harness for spec §7; project.yml → generated .xcodeproj (ignored)
  findings/            one markdown file per spike result, from findings/TEMPLATE.md
docs/superpowers/
  specs/               design specs (the source of truth for what gets built)
  plans/               implementation plans, one file per plan, plus the roadmap
.github/workflows/     CI: swift test + license guard; Readium package on the simulator
```

Ignored and regenerated, so they may appear in an editor but never in git:
`.build/` (SwiftPM and xcodebuild output, in every package), `.swiftpm/`,
`.superpowers/` (planning-tool scratch),
`spikes/SpikeHarness/SpikeHarness.xcodeproj/` (from `project.yml`), the
model files under `spikes/SpikeHarness/Resources/` (see `spikes/README.md`),
and `App/T2SReader.xcodeproj/` and `App/T2SReader/Info.plist` (from
`App/project.yml`).

## Rules that keep this tidy

- One `.gitignore`, at the root.
- Generated files are never committed: project files come from `project.yml`,
  build output from SwiftPM and xcodebuild.
- New code goes in a target under `Sources/` with its tests under `Tests/`;
  code that needs an iOS-only dependency goes in a package under `Packages/`;
  `spikes/` is for experiments only.
- Every plan lives in `docs/superpowers/plans/`; every spec in
  `docs/superpowers/specs/`. Spike results go in `spikes/findings/`.

## Working on it

```bash
swift test                     # the root package, on macOS
scripts/test-readium.sh        # Packages/T2SReadium on an iPhone simulator
scripts/check-licenses.sh      # fails on any copyleft dependency, in every package
cd spikes/SpikeHarness && xcodegen generate && open SpikeHarness.xcodeproj
scripts/build-app.sh           # regenerate App/T2SReader.xcodeproj and build for the simulator
open App/T2SReader.xcodeproj   # after scripts/build-app.sh has generated it
scripts/fetch-readability.sh   # re-vendor Readability.js (committed under App/Resources/Readability)
```
