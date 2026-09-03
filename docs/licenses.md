# Third-party licence register

Every third-party component shipped in, or linked into, the app. Vendored sources are audited by
hand here (`scripts/check-licenses.sh` only sees SPM checkouts); the script fails the build if any
SPM dependency is copyleft. Nothing below is copyleft.

Each row was read from the LICENSE file at the path given; versions for SPM packages are the
resolved tags in `Packages/T2SReadium/.build/checkouts` (the app resolves the same graph).

## Vendored into the repository

| Component | Version | Licence | LICENSE file |
| --- | --- | --- | --- |
| Inter (5 TTFs) | 4.1 | SIL Open Font License 1.1 | `App/Resources/Fonts/LICENSE.txt` |
| Readability.js | 0.6.0 | Apache-2.0 | `App/Resources/Readability/LICENSE` |

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

## Attribution obligations to honour before shipping

- **Inter** (OFL 1.1): the font files may be embedded; the reserved font name must not be reused for
  a modified build, and the licence text ships with the app.
- **Readability.js**, **DifferenceKit** (Apache-2.0): retain the copyright and licence notices.
- **CryptoSwift**: its licence asks for an acknowledgment of the author in product documentation.
- **Readium**, **GCDWebServer** (BSD-3): retain the copyright notice; do not use the names to
  endorse a derived product.

An About / Acknowledgements screen carrying these notices is not built yet (Preferences is a
placeholder in Plan 4a); it is a prerequisite for any TestFlight or App Store build.
