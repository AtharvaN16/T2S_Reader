# MLXUtilsLibrary (vendored)

`github.com/mlalma/MLXUtilsLibrary` at `41f6cfd5d68b65aa3c65a34efe3b71c371ed915b` (tag 0.0.6),
Apache-2.0 — see `LICENSE`. `kokoro-ios` and `MisakiSwift` both pin this package `exact: "0.0.6"`;
because a package's SwiftPM identity is its directory name, this local copy takes over the identity
`mlxutilslibrary` for the whole graph.

It exists for one reason: upstream depends on `weichsel/ZIPFoundation` (0.9.x) while Readium depends
on `readium/ZIPFoundation` (3.x). SwiftPM derives identity from a repository's last path component,
so both collapse onto `zipfoundation` with disjoint version ranges and the app — which needs Readium
*and* Kokoro — cannot resolve at all.

Patched, and nothing else: `NpyzReader.unarchive(data:)` reads `voices.npz` through our own
`NpzArchive` rather than ZIPFoundation. Every public API and behaviour is upstream's. The exit plan
is an upstream PR dropping ZIPFoundation, after which this directory goes.
