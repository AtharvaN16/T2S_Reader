# Spikes

Throwaway harnesses for spec §7. Nothing under `spikes/` is imported by shipping code.

## SpikeHarness (iOS)

Generated Xcode project; `project.yml` is the source of truth.

```bash
brew install xcodegen                      # once
cd spikes/SpikeHarness
xcodegen generate
open SpikeHarness.xcodeproj                # set your team under Signing & Capabilities, then run on a device
```

The app does not run in the simulator: MLX needs a real GPU.

### Model files (not committed)

Two files go in `spikes/SpikeHarness/Resources/` and are gitignored:

| File | Source | Size | SHA-256 |
|---|---|---|---|
| `kokoro-v1_0.safetensors` | `https://media.githubusercontent.com/media/mlalma/KokoroTestApp/main/Resources/kokoro-v1_0.safetensors` | 327,115,152 bytes | `4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8` |
| `voices.npz` | `https://raw.githubusercontent.com/mlalma/KokoroTestApp/main/Resources/voices.npz` | 14,629,684 bytes | — (28 voice styles) |

```bash
cd spikes/SpikeHarness/Resources
curl -sSL -o kokoro-v1_0.safetensors https://media.githubusercontent.com/media/mlalma/KokoroTestApp/main/Resources/kokoro-v1_0.safetensors
curl -sSL -o voices.npz https://raw.githubusercontent.com/mlalma/KokoroTestApp/main/Resources/voices.npz
shasum -a 256 kokoro-v1_0.safetensors     # must match the table
```

Weights are Kokoro-82M (Apache 2.0) as packaged by KokoroTestApp (Apache 2.0).

### Dependencies

| Package | Pin | License |
|---|---|---|
| kokoro-ios (`KokoroSwift`) | 1.0.11 (`4d6d1d8ff8cd`) | MIT |
| MLXUtilsLibrary | 0.0.6 | see repo |
| mlx-swift (transitive) | 0.30.2 | MIT |
| MisakiSwift (transitive) | 1.0.6 | Apache 2.0 — the spec calls it MIT; correct that in the §7.1 audit |

### Reading the log

Each run writes `spike-<epoch>.csv` to the app's Documents folder (Files → On My iPhone → Spike Harness).
Columns: `ts,event,k,v`. Events: `app.launch`, `model.loaded`, `bench.start`, `sentence`, `timing`, `bench.stop`.
Analyse with `python3 spikes/analyze.py spike-*.csv` (added in Plan 0 Task 4).
