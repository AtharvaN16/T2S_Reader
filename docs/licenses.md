# Third-party licence register

Every third-party component shipped in, or linked into, the app. Vendored sources are audited by
hand here (`scripts/check-licenses.sh` only sees SPM checkouts); the script fails the build if any
SPM dependency is copyleft. Nothing below is copyleft.

Each row was read from the LICENSE file at the path given; versions for SPM packages are the
resolved tags in `Packages/T2SReadium/.build/checkouts` and `Packages/T2SKokoro/.build/checkouts`
(the app resolves the same graph).

## Vendored into the repository

| Component | Version | Licence | LICENSE file |
| --- | --- | --- | --- |
| Inter (5 TTFs) | 4.1 | SIL Open Font License 1.1 | `App/Resources/Fonts/LICENSE.txt` |
| Readability.js | 0.6.0 | Apache-2.0 | `App/Resources/Readability/LICENSE` |
| MLXUtilsLibrary | 0.0.6 + our patch | Apache-2.0 | `Packages/MLXUtilsLibrary/LICENSE` |
| KokoroPipeline | `mattmireles/kokoro-coreml` @ `66d8cf5108cce0991b8868b01b4d8a8b2e98881d` | Apache-2.0 | `Packages/KokoroPipeline/LICENSE` |

## Swift Package Manager

Declared directly by `Packages/T2SReadium/Package.swift` and `App/project.yml`:

| Component | Version | Licence | LICENSE file |
| --- | --- | --- | --- |
| Readium swift-toolkit | 3.11.0 | BSD-3-Clause | `Packages/T2SReadium/.build/checkouts/swift-toolkit/LICENSE` |

Pulled in transitively by the Readium toolkit (the set `scripts/check-licenses.sh` walks):

| Component | Version | Licence | LICENSE file (under `Packages/T2SReadium/.build/checkouts/`) |
| --- | --- | --- | --- |
| CryptoSwift | 1.10.0 | zlib-style permissive (attribution required) | `CryptoSwift/LICENSE` |
| DifferenceKit | 1.3.0 | Apache-2.0 | `DifferenceKit/LICENSE` |
| Fuzi | 4.0.1 | MIT | `Fuzi/LICENSE` |
| GCDWebServer | 4.0.1 | BSD-3-Clause | `GCDWebServer/LICENSE` |
| SQLite.swift | 0.16.0 | MIT | `SQLite.swift/LICENSE.txt` |
| SwiftSoup | 2.13.9 | MIT | `SwiftSoup/LICENSE` |
| ZIPFoundation | 3.0.1 | MIT | `ZIPFoundation/LICENSE` |
| Zip | 2.1.2 | MIT | `Zip/LICENSE` |

## Kokoro path (linked by the app target from Plan 5 Task 5)

Declared by `Packages/T2SKokoro/Package.swift` — `kokoro-ios`, `MLXUtilsLibrary` and
`KokoroPipeline` directly, the rest transitively — at the same pins the Plan 0 spike harness
measured. Audited 2026-09-03 from the LICENSE files (KokoroPipeline and the Core ML model files
added 2026-09-04). The spec's §7.1 note that MisakiSwift is MIT is wrong; it is Apache-2.0.

MLXUtilsLibrary and KokoroPipeline are the vendored copies above rather than SPM checkouts (see
their READMEs); vendoring MLXUtilsLibrary also takes ZIPFoundation 0.9.20 off this path, where it
was only ever there to open `voices.npz`.

| Component | Version | Licence | LICENSE file (under `Packages/T2SKokoro/.build/checkouts/`) |
| --- | --- | --- | --- |
| kokoro-ios (`KokoroSwift`) | 1.0.11 | MIT | `kokoro-ios/LICENSE` |
| mlx-swift | 0.30.2 | MIT | `mlx-swift/LICENSE` |
| MisakiSwift | 1.0.6 | Apache-2.0 | `MisakiSwift/LICENSE` |
| MLXUtilsLibrary | 0.0.6 + patch | Apache-2.0 | vendored — `Packages/MLXUtilsLibrary/LICENSE` |
| KokoroPipeline | `kokoro-coreml` @ `66d8cf51` | Apache-2.0 | vendored — `Packages/KokoroPipeline/LICENSE` |
| swift-numerics | 1.1.1 | Apache-2.0 | `swift-numerics/LICENSE.txt` |
| Kokoro-82M weights (`kokoro-v1_0.safetensors`) | KokoroTestApp packaging | Apache-2.0 | see `spikes/README.md` and `scripts/fetch-kokoro-model.sh` |
| Core ML model files (`App/Resources/KokoroCoreML/`: 8 `.mlpackage` stages, 28 voices, 2 runtime JSONs) | `mattmireles/kokoro-coreml` HF revision `2e878c6a` | Apache-2.0, inherited from Kokoro-82M | conversion `Packages/KokoroPipeline/LICENSE`; weights as for the row above — installed by `scripts/fetch-kokoro-coreml.sh --app`, never committed |

No copyleft on this path. Apache-2.0 entries carry the same notice-retention obligation as
Readability.js below; the weights' licence must ship alongside them if they are bundled.

## Attribution obligations to honour before shipping

- **Inter** (OFL 1.1): the font files may be embedded; the reserved font name must not be reused for
  a modified build, and the licence text ships with the app.
- **Readability.js**, **DifferenceKit**, **MisakiSwift**, **MLXUtilsLibrary**, **KokoroPipeline**,
  **swift-numerics** (Apache-2.0): retain the copyright and licence notices.
- **Kokoro-82M weights** (Apache-2.0), including the Core ML conversions the app bundles from
  `App/Resources/KokoroCoreML/`: retain the notice, and ship the licence text alongside the weights.
- **CryptoSwift**: its licence asks for an acknowledgment of the author in product documentation.
- **Readium**, **GCDWebServer** (BSD-3): retain the copyright notice; do not use the names to
  endorse a derived product.

An About / Acknowledgements screen carrying these notices is not built yet (Preferences is a
placeholder in Plan 4a); it is a prerequisite for any TestFlight or App Store build.
