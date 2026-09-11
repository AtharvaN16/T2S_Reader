import Foundation

/// Every file of the Core ML Kokoro model the app installs: the fourteen staged `.mlpackage`s (three
/// files each), the 28 English voices and the two runtime JSON files — 72 files, 354,636,158 bytes —
/// at the pinned Hugging Face revision, each with the SHA-256 the download is checked against.
///
/// The weights are int8: `scripts/quantize-kokoro-coreml.py` compresses the upstream float16 export
/// and `scripts/stage-kokoro-release.py` publishes it, which is why the repository is ours rather
/// than `mattmireles/kokoro-coreml` — we cannot add a revision to someone else's. The graphs are
/// unchanged from upstream's `2e878c6a` export; only the weight encoding differs, and Core ML
/// expands it back to float16 at load, so nothing downstream of the download notices.
///
/// Every row here was generated from the staged files and then checked against the published tree,
/// so no hash is hand-copied. No row needs a `repositoryPath`: our layout is uniform, where upstream
/// kept 7 voices under `voices/` and the other 21 under `kokoro.js/voices/`.
///
/// `scripts/fetch-kokoro-coreml.sh` still stages the *float16* files for the tests and the probes,
/// which is deliberate — the quantization probe compares the two, so both have to exist.
/// A moved pin changes ``KokoroCoreMLResources/modelRevision``, and this table with it.
public enum KokoroCoreMLManifest {
    /// One file to install: where it lands under the staging root, where it lives in the repository,
    /// and what it must hash to.
    public struct File: Hashable, Sendable {
        /// The path under the staging root: `coreml/<stage>.mlpackage/...`, `voices/<name>.bin`,
        /// `runtime/<file>.json`.
        public let path: String
        /// The path in the Hugging Face repository at ``KokoroCoreMLResources/modelRevision``.
        public let repositoryPath: String
        public let sha256: String
        public let byteCount: Int

        public init(_ path: String, repositoryPath: String? = nil, sha256: String, byteCount: Int) {
            self.path = path
            self.repositoryPath = repositoryPath ?? path
            self.sha256 = sha256
            self.byteCount = byteCount
        }

        /// The file's download URL at the pinned revision.
        public var url: URL {
            KokoroCoreMLManifest.repositoryURL
                .appending(path: "resolve/\(KokoroCoreMLResources.modelRevision)/\(repositoryPath)")
        }
    }

    public static let repositoryURL = URL(string: "https://huggingface.co/anayak16/kokoro-coreml-int8")!

    public static var totalByteCount: Int { files.reduce(0) { $0 + $1.byteCount } }

    public static let files: [File] = [
    File("coreml/kokoro_decoder_har_post_10s.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "a202bf4e07c8cd6612d7daf321bc21246ad3d9c9959bf5c99aa0c70ff21eed50", byteCount: 364704),
    File("coreml/kokoro_decoder_har_post_10s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "10923a669c60c125fb641d26413b0a344b0ba06a2f5d4a25123be2ff7b022731", byteCount: 22831800),
    File("coreml/kokoro_decoder_har_post_10s.mlpackage/Manifest.json", sha256: "4ae75dd269821f678d6e0cf7102452b5849745a95a444d754c556eed94525cf6", byteCount: 617),
    File("coreml/kokoro_decoder_har_post_15s.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "a0b05b447e47da489c8814f66bc57759c3de7c313855e2da2dd62d8fddf07a0b", byteCount: 364804),
    File("coreml/kokoro_decoder_har_post_15s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "10923a669c60c125fb641d26413b0a344b0ba06a2f5d4a25123be2ff7b022731", byteCount: 22831800),
    File("coreml/kokoro_decoder_har_post_15s.mlpackage/Manifest.json", sha256: "50d3a278b832ad969d9ea7ca9906fb680c2ebd635b342fda84e46f6494bb6e07", byteCount: 617),
    File("coreml/kokoro_decoder_har_post_3s.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "22d37ec985a2a792cca20c78411b588833c1341cf7ea7b0e05aeb953aaca7667", byteCount: 364391),
    File("coreml/kokoro_decoder_har_post_3s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "10923a669c60c125fb641d26413b0a344b0ba06a2f5d4a25123be2ff7b022731", byteCount: 22831800),
    File("coreml/kokoro_decoder_har_post_3s.mlpackage/Manifest.json", sha256: "ab90f04a8f35dc2ec726c9d90d0532ffedbf04ee0513daea85b0322f3272b9ea", byteCount: 617),
    File("coreml/kokoro_decoder_har_post_7s.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "f9bd8a9d87f1b832c8052146d423b593aea8356f35d1b7221adff9076103f1aa", byteCount: 364704),
    File("coreml/kokoro_decoder_har_post_7s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "10923a669c60c125fb641d26413b0a344b0ba06a2f5d4a25123be2ff7b022731", byteCount: 22831800),
    File("coreml/kokoro_decoder_har_post_7s.mlpackage/Manifest.json", sha256: "7035957618e811aa5ef3a0e396007c3e4b85d5289c5fe01a8ab348c2b78a30a2", byteCount: 617),
    File("coreml/kokoro_decoder_pre_10s.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "062c740f370059ddb176d9a319f7be34f830f5578279e8d557faecef29afeb72", byteCount: 80053),
    File("coreml/kokoro_decoder_pre_10s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "e92eb494573fdb88f286b764d769ca9fbad2f8d81cd3091b01d120b353b69866", byteCount: 33704896),
    File("coreml/kokoro_decoder_pre_10s.mlpackage/Manifest.json", sha256: "df51a4c8908fb70834ac4d5eae67d822bb2a64f6cba8de751dc01494f5d17e72", byteCount: 617),
    File("coreml/kokoro_decoder_pre_15s.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "7c41dd3339919d5455873c86a4429194e66efb2f3677fa99a34341e6c860d935", byteCount: 80053),
    File("coreml/kokoro_decoder_pre_15s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "e92eb494573fdb88f286b764d769ca9fbad2f8d81cd3091b01d120b353b69866", byteCount: 33704896),
    File("coreml/kokoro_decoder_pre_15s.mlpackage/Manifest.json", sha256: "b127e883dc6a481ca85dd360d94f5ea81e8c8b47d77c74a8a9dfd0a9753449f8", byteCount: 617),
    File("coreml/kokoro_decoder_pre_3s.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "97d1898455f7334023329b994ea6c78254916dd87eecbc3fb6223350fdb79a8b", byteCount: 79922),
    File("coreml/kokoro_decoder_pre_3s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "e92eb494573fdb88f286b764d769ca9fbad2f8d81cd3091b01d120b353b69866", byteCount: 33704896),
    File("coreml/kokoro_decoder_pre_3s.mlpackage/Manifest.json", sha256: "307a9ca8aec18a288dacec8aab7046f47f1afc4fb843d11f3657589fda5f37fb", byteCount: 617),
    File("coreml/kokoro_decoder_pre_7s.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "e6ab39e126ee990dafbcbea2e221223a9dabb54a710b6776a37e449746cfa445", byteCount: 80053),
    File("coreml/kokoro_decoder_pre_7s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "e92eb494573fdb88f286b764d769ca9fbad2f8d81cd3091b01d120b353b69866", byteCount: 33704896),
    File("coreml/kokoro_decoder_pre_7s.mlpackage/Manifest.json", sha256: "56394b633af4bd60134cf7622f6d23002ad5e8670ecda3385433e83343e6c0b1", byteCount: 617),
    File("coreml/kokoro_duration_t128.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "75137f8c9a734076320559b8d68da597b355581cd9d3d42bd2b3ff35dc595409", byteCount: 5575191),
    File("coreml/kokoro_duration_t128.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "a3b1578be708f34538260604e9cc3ee6a85b77b2e79bd249b0ee9fc82bebbeb3", byteCount: 19584576),
    File("coreml/kokoro_duration_t128.mlpackage/Manifest.json", sha256: "1f65c57d20d7e6f2142ac46b7ecb491e9cc030ed203622c03b4f8601a92067cc", byteCount: 617),
    File("coreml/kokoro_duration_t256.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "ded3e4cfdc22de82111e6cdc134560bf3ca8a706655beca7be5b37dfcd397c78", byteCount: 11040119),
    File("coreml/kokoro_duration_t256.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "680d8415697cc2d7c730c62ffea60f1e10c46fc4ddf374b0effc2809a1537dc4", byteCount: 19617344),
    File("coreml/kokoro_duration_t256.mlpackage/Manifest.json", sha256: "f5e8eaddc0ed31b8eae594c7cd10ff928b9a714c5b2e6b405954aba6ed1981c4", byteCount: 617),
    File("coreml/kokoro_f0ntrain_t120.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "af1bd2b76c43bfd8744f23a20254d847e5f88bff578fbba17e102baa1fdc2163", byteCount: 89987),
    File("coreml/kokoro_f0ntrain_t120.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "2c6fa18b484b1851fd8911ddea0e16887ca48cecf12a0a890950236de04526b3", byteCount: 13975104),
    File("coreml/kokoro_f0ntrain_t120.mlpackage/Manifest.json", sha256: "76d28a2134f563f7117c873b04d04144bfc6bfdaa2403857029fae76094e4c15", byteCount: 617),
    File("coreml/kokoro_f0ntrain_t280.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "726b9ce9bec6bcbfcbd9d25502ae4b0b2be23de8304b80f7c577314d43e2c857", byteCount: 90068),
    File("coreml/kokoro_f0ntrain_t280.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "2c6fa18b484b1851fd8911ddea0e16887ca48cecf12a0a890950236de04526b3", byteCount: 13975104),
    File("coreml/kokoro_f0ntrain_t280.mlpackage/Manifest.json", sha256: "427ad6ac276ca5851d3a256d9f718b77d3aad8fc4a6f5061445bc6afa1fd1b97", byteCount: 617),
    File("coreml/kokoro_f0ntrain_t400.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "067b685198ee18c261e7c65183e426570b7b8695c54830fe7a4e518e06486e50", byteCount: 90068),
    File("coreml/kokoro_f0ntrain_t400.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "2c6fa18b484b1851fd8911ddea0e16887ca48cecf12a0a890950236de04526b3", byteCount: 13975104),
    File("coreml/kokoro_f0ntrain_t400.mlpackage/Manifest.json", sha256: "577f77638a6103b95658abddf40ed102cfd2ce4ec36632b2e86ccfcaedfc7061", byteCount: 617),
    File("coreml/kokoro_f0ntrain_t600.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "99798da577999837ec87981dac48a16a807aa8d1e3734cadb726e9b0b19b9805", byteCount: 90068),
    File("coreml/kokoro_f0ntrain_t600.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "2c6fa18b484b1851fd8911ddea0e16887ca48cecf12a0a890950236de04526b3", byteCount: 13975104),
    File("coreml/kokoro_f0ntrain_t600.mlpackage/Manifest.json", sha256: "7c55206c563c9b2541b3c4786f946b63515308460d5acbfa4454366c2b3a3f45", byteCount: 617),
    File("runtime/hnsf_weights.json", sha256: "de73b717732da77b31736f67a108d35c478ab116b0a188e9787019b0408c0226", byteCount: 336),
    File("runtime/kokoro-vocab.json", sha256: "353ca94410fde4575cb091a0ba32b8e99077fde4f38fded506f4f041d22571a3", byteCount: 1159),
    File("voices/af_alloy.bin", sha256: "c4a6b876047fd7fb472edf4ebd63cfac7c3b958a7cae7c106e8f038ca6308c45", byteCount: 522240),
    File("voices/af_aoede.bin", sha256: "4a004c33430762e2461eedb2013fad808ef4ab3121f5300f554476caf58d8361", byteCount: 522240),
    File("voices/af_bella.bin", sha256: "f69d836209b78eb8c66e75e3cda491e26ea838a3674257e9d4e5703cbaf55c8b", byteCount: 522240),
    File("voices/af_heart.bin", sha256: "d583ccff3cdca2f7fae535cb998ac07e9fcb90f09737b9a41fa2734ec44a8f0b", byteCount: 522240),
    File("voices/af_jessica.bin", sha256: "a240a5e3c15b43563d6e923bdca8ef5613a23471d9b77653694012435df23bd8", byteCount: 522240),
    File("voices/af_kore.bin", sha256: "9be5221b6a941c04b561959b8ff0b06e809444dcc4ab7e75a7b23606f691819e", byteCount: 522240),
    File("voices/af_nicole.bin", sha256: "cd2191ab31b914ed7b318416b0e4440fdf392ddad9106a060819aa600a64f59a", byteCount: 522240),
    File("voices/af_nova.bin", sha256: "18778272caa0d0eebaea251c35fd635f038434f9eee5e691d02a174bd328414f", byteCount: 522240),
    File("voices/af_river.bin", sha256: "00a2bcf82b1d86e8f19902ede58c65ccf6c0e43b44b7d74fad54e5d8933c9c30", byteCount: 522240),
    File("voices/af_sarah.bin", sha256: "4409fbc125afabacc615d94db5398d847006a737b0247d6892b7a9a0007a2f0a", byteCount: 522240),
    File("voices/af_sky.bin", sha256: "4435255c9744f3f31659e0d714ab7689bf65d9e77ec1cce060f083912614f0b9", byteCount: 522240),
    File("voices/am_adam.bin", sha256: "162b035ed91cfc48b6046982184c645f72edcdd1b82843347f605d7bf7b15716", byteCount: 522240),
    File("voices/am_echo.bin", sha256: "3968b92c3c4cd1c4416dbded36c13eaa388a90d5788d02a13e4d781f5f8cf3c3", byteCount: 522240),
    File("voices/am_eric.bin", sha256: "e8b5be17edd1e3636901ce7598baafe2dc8dd8ff707a0c23bf9e461add7e2832", byteCount: 522240),
    File("voices/am_fenrir.bin", sha256: "c27989f741f7ee34d273a39d8a595cc0837d35f5ced9a29b7cc162614616df43", byteCount: 522240),
    File("voices/am_liam.bin", sha256: "52403be32fd047c6a44517cb0bcd6b134f2a18baa73e70ef41651e0eab921ade", byteCount: 522240),
    File("voices/am_michael.bin", sha256: "1d1f21dd8da39c30705cd4c75d039d265e9bc4a2a93ed09bc9e1b1225eb95ba1", byteCount: 522240),
    File("voices/am_onyx.bin", sha256: "da5d135b424164916d75a68ffb4c2abce3d7d5ccc82dd1ee6cf447ce286145e6", byteCount: 522240),
    File("voices/am_puck.bin", sha256: "fcf73c989033e9233e0b98713eca600c8c74dcc1614b37009d5450ff4a2274a0", byteCount: 522240),
    File("voices/am_santa.bin", sha256: "61150cf726ab6c5ed7a99f90a304f91f5a72c00c592e89ec94e5df11c319227a", byteCount: 522240),
    File("voices/bf_alice.bin", sha256: "08afa6ba24da61ea5e8efa139e5aadc938d83f0a6da5a900adaf763ac1da5573", byteCount: 522240),
    File("voices/bf_emma.bin", sha256: "669fe0647f9dd04fcab92f1439a40eeb4c8b4ab1f82e4996fe3d918ce4a63b73", byteCount: 522240),
    File("voices/bf_isabella.bin", sha256: "3754352c4aaa46d17f27654ab7518d65b62ad6163a0f55a5f4330c2da2c4e94f", byteCount: 522240),
    File("voices/bf_lily.bin", sha256: "5e0ee32ebe64a467124976b14e69590746f1c4ce41a12b587a50c862edfea335", byteCount: 522240),
    File("voices/bm_daniel.bin", sha256: "6b3194bbceffb746733cbc22c8f593dd44e401a71d53895a2dca891bc595a1e8", byteCount: 522240),
    File("voices/bm_fable.bin", sha256: "f889083196807b4adb15e9204252165f503b8d33d3982e681c52443c49d798f1", byteCount: 522240),
    File("voices/bm_george.bin", sha256: "c4b235a4c1f2cd3b939fed08b899ce9385638b763f7b73a59616c4fc9bd6c9bc", byteCount: 522240),
    File("voices/bm_lewis.bin", sha256: "b8f671cef828c30e66fdf0b0756a76bba58f6bb3398cbbf27058642acbcedb97", byteCount: 522240),
    ]
}
