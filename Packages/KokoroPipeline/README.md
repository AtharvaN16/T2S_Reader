# KokoroPipeline (vendored)

`github.com/mattmireles/kokoro-coreml` at `66d8cf5108cce0991b8868b01b4d8a8b2e98881d` (main,
2026-08-28), Apache-2.0 — see `LICENSE`. `Sources/KokoroPipeline/` is unchanged: every file is
byte-identical to upstream's `swift/Sources/KokoroPipeline/`.

It exists for one reason: the upstream repository root has no `Package.swift` — the package lives
in the `swift/` subdirectory, and SwiftPM cannot consume a subdirectory of a repository by URL.

`Package.swift` is ours and differs from upstream's only by subtraction: the two `kokoro-bench`
executable products and their targets go, and upstream's test target (whose fixtures we do not
vendor) is replaced by `Tests/KokoroPipelineTests`. Tools version and platform floors are upstream's.
The exit plan is to depend on the repo by URL if upstream ever moves its manifest to the root.
